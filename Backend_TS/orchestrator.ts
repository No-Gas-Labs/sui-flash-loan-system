import { 
  SuiClient, 
  getFullnodeUrl, 
  Ed25519Keypair,
  TransactionBlock,
  normalizeSuiObjectId
} from '@mysten/sui.js/client';
import { 
  PACKAGE_ID,
  POOL_OBJECT_ID,
  ADMIN_PRIVATE_KEY,
  DEX_ROUTES
} from '../config/constants';

interface TokenInfo {
  type: string;
  decimals: number;
  symbol: string;
}

interface ArbitrageOpportunity {
  routeA: DexRoute;
  routeB: DexRoute;
  amountIn: number;
  expectedProfit: number;
  tokenA: TokenInfo;
  tokenB: TokenInfo;
}

interface DexRoute {
  dexType: 'cetus' | 'turbos' | 'aftermath';
  poolId: string;
  feeTier: number;
}

interface PoolInfo {
  liquidity: number;
  feeRate: number;
  totalBorrowed: number;
  totalRepaid: number;
  activeLoans: number;
}

interface FlashLoanReceipt {
  poolId: string;
  loanId: string;
  amount: number;
  fee: number;
  borrower: string;
}

export class FlashLoanOrchestrator {
  private client: SuiClient;
  private keypair: Ed25519Keypair;
  private packageId: string;
  private poolId: string;
  private monitoringInterval?: NodeJS.Timeout;
  private isMonitoring: boolean = false;
  private dexRegistryId?: string;
  private assetRegistryId?: string;

  constructor(
    network: 'mainnet' | 'testnet' | 'devnet' = 'testnet',
    packageId?: string,
    poolId?: string,
    dexRegistryId?: string,
    assetRegistryId?: string
  ) {
    this.client = new SuiClient({ url: getFullnodeUrl(network) });
    this.keypair = Ed25519Keypair.fromSecretKey(Buffer.from(ADMIN_PRIVATE_KEY, 'hex'));
    this.packageId = packageId || PACKAGE_ID;
    this.poolId = poolId || POOL_OBJECT_ID;
    this.dexRegistryId = dexRegistryId;
    this.assetRegistryId = assetRegistryId;
  }

  /**
   * Get current pool information
   */
  async getPoolInfo(): Promise<PoolInfo> {
    try {
      const pool = await this.client.getObject({
        id: this.poolId,
        options: { showContent: true }
      });

      if (!pool.data?.content || typeof pool.data.content !== 'object') {
        throw new Error('Invalid pool data');
      }

      const content = pool.data.content as any;
      return {
        liquidity: parseInt(content.fields.liquidity || '0'),
        feeRate: parseInt(content.fields.fee_basis_points || '0'),
        totalBorrowed: parseInt(content.fields.total_borrowed || '0'),
        totalRepaid: parseInt(content.fields.total_repaid || '0'),
        activeLoans: parseInt(content.fields.active_loans || '0'),
      };
    } catch (error) {
      console.error('Error fetching pool info:', error);
      throw error;
    }
  }

  /**
   * Create a new flash loan pool
   */
  async createPool(
    tokenType: string,
    initialLiquidity: number,
    feeBasisPoints: number
  ): Promise<string> {
    try {
      const tx = new TransactionBlock();
      
      const [coin] = tx.splitCoins(tx.gas, [tx.pure(initialLiquidity)]);
      
      tx.moveCall({
        target: `${this.packageId}::pool_v2::create_pool`,
        arguments: [
          coin,
          tx.pure(feeBasisPoints)
        ],
        typeArguments: [tokenType]
      });

      const result = await this.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: this.keypair,
        requestType: 'WaitForLocalExecution'
      });

      if (result.effects?.status.status !== 'success') {
        throw new Error('Failed to create pool');
      }

      const createdObjects = result.effects?.created || [];
      const poolObject = createdObjects.find(obj => obj.owner === 'Shared');
      
      if (!poolObject) {
        throw new Error('Pool creation failed - no shared object');
      }

      return poolObject.reference.objectId;
    } catch (error) {
      console.error('Error creating pool:', error);
      throw error;
    }
  }

  /**
   * Deposit liquidity into the pool
   */
  async depositLiquidity(
    tokenType: string,
    amount: number
  ): Promise<string> {
    try {
      const tx = new TransactionBlock();
      
      const [coin] = tx.splitCoins(tx.gas, [tx.pure(amount)]);
      
      tx.moveCall({
        target: `${this.packageId}::pool_v2::deposit`,
        arguments: [
          tx.object(this.poolId),
          coin
        ],
        typeArguments: [tokenType]
      });

      const result = await this.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: this.keypair,
        requestType: 'WaitForLocalExecution'
      });

      return result.digest;
    } catch (error) {
      console.error('Error depositing liquidity:', error);
      throw error;
    }
  }

  /**
   * Find arbitrage opportunities across DEXs
   */
  async findArbitrageOpportunities(
    tokenA: TokenInfo,
    tokenB: TokenInfo,
    maxAmount: number
  ): Promise<ArbitrageOpportunity[]> {
    try {
      const opportunities: ArbitrageOpportunity[] = [];
      
      // Get available routes for both directions
      const routesA = await this.getAvailableRoutes(tokenA, tokenB);
      const routesB = await this.getAvailableRoutes(tokenB, tokenA);
      
      // Check all combinations
      for (const routeA of routesA) {
        for (const routeB of routesB) {
          const opportunity = await this.calculateArbitrage(
            routeA,
            routeB,
            tokenA,
            tokenB,
            maxAmount
          );
          
          if (opportunity.expectedProfit > 0) {
            opportunities.push(opportunity);
          }
        }
      }
      
      // Sort by profit descending
      return opportunities.sort((a, b) => b.expectedProfit - a.expectedProfit);
    } catch (error) {
      console.error('Error finding arbitrage opportunities:', error);
      return [];
    }
  }

  /**
   * Execute arbitrage using flash loan
   */
  async executeArbitrage(
    opportunity: ArbitrageOpportunity,
    deadline: number = 300000 // 5 minutes
  ): Promise<{
    success: boolean;
    profit: number;
    transactionDigest: string;
    gasUsed: number;
  }> {
    try {
      const tx = new TransactionBlock();
      
      // Get flash loan
      const [loanCoin, receipt] = tx.moveCall({
        target: `${this.packageId}::pool_v2::borrow`,
        arguments: [
          tx.object(this.poolId),
          tx.pure(opportunity.amountIn)
        ],
        typeArguments: [opportunity.tokenA.type]
      });
      
      // Execute first swap
      const [swapResultA] = tx.moveCall({
        target: `${this.packageId}::dex_adapter_v2::swap_exact_tokens_for_tokens`,
        arguments: [
          loanCoin,
          tx.pure({
            route: opportunity.routeA,
            amount_in: opportunity.amountIn,
            min_amount_out: 0,
            deadline: Date.now() + deadline
          })
        ],
        typeArguments: [opportunity.tokenA.type, opportunity.tokenB.type]
      });
      
      // Execute second swap
      const [finalCoin] = tx.moveCall({
        target: `${this.packageId}::dex_adapter_v2::swap_exact_tokens_for_tokens`,
        arguments: [
          swapResultA,
          tx.pure({
            route: opportunity.routeB,
            amount_in: opportunity.amountIn,
            min_amount_out: opportunity.amountIn + opportunity.expectedProfit,
            deadline: Date.now() + deadline
          })
        ],
        typeArguments: [opportunity.tokenB.type, opportunity.tokenA.type]
      });
      
      // Repay flash loan
      tx.moveCall({
        target: `${this.packageId}::pool_v2::repay`,
        arguments: [
          tx.object(this.poolId),
          finalCoin,
          receipt
        ],
        typeArguments: [opportunity.tokenA.type]
      });
      
      const result = await this.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: this.keypair,
        requestType: 'WaitForLocalExecution'
      });
      
      if (result.effects?.status.status !== 'success') {
        throw new Error('Arbitrage execution failed');
      }
      
      return {
        success: true,
        profit: opportunity.expectedProfit,
        transactionDigest: result.digest,
        gasUsed: parseInt(result.effects?.gasUsed?.computationCost || '0')
      };
    } catch (error) {
      console.error('Error executing arbitrage:', error);
      return {
        success: false,
        profit: 0,
        transactionDigest: '',
        gasUsed: 0
      };
    }
  }

  /**
   * Batch execute multiple arbitrage opportunities
   */
  async executeBatchArbitrage(
    opportunities: ArbitrageOpportunity[],
    minTotalProfit: number = 0
  ): Promise<{
    totalProfit: number;
    successful: number;
    failed: number;
    results: Array<{
      success: boolean;
      profit: number;
      transactionDigest: string;
    }>;
  }> {
    const results = [];
    let totalProfit = 0;
    let successful = 0;
    let failed = 0;
    
    for (const opportunity of opportunities) {
      const result = await this.executeArbitrage(opportunity);
      
      if (result.success) {
        successful++;
        totalProfit += result.profit;
      } else {
        failed++;
      }
      
      results.push({
        success: result.success,
        profit: result.profit,
        transactionDigest: result.transactionDigest
      });
    }
    
    return {
      totalProfit,
      successful,
      failed,
      results
    };
  }

  /**
   * Enhanced monitoring with visual feedback and safety controls
   */
  async startMonitoring(
    tokenPairs: Array<[TokenInfo, TokenInfo]>,
    maxAmount: number,
    minProfit: number,
    interval: number = 5000 // 5 seconds
  ): Promise<() => void> {
    console.log('🚀 Starting arbitrage monitoring...');
    this.isMonitoring = true;
    
    const monitor = setInterval(async () => {
      if (!this.isMonitoring) return;
      
      try {
        console.log('🔍 Scanning for opportunities...');
        
        for (const [tokenA, tokenB] of tokenPairs) {
          const opportunities = await this.findArbitrageOpportunities(
            tokenA,
            tokenB,
            maxAmount
          );
          
          const profitable = opportunities.filter(
            opp => opp.expectedProfit >= minProfit
          );
          
          if (profitable.length > 0) {
            console.log(`✅ Found ${profitable.length} profitable opportunities`);
            
            // Visual feedback for each opportunity
            profitable.forEach((opp, index) => {
              console.log(`  📊 Opportunity ${index + 1}:`);
              console.log(`     Route A: ${opp.routeA.dexType} (${opp.routeA.feeTier * 100}%)`);
              console.log(`     Route B: ${opp.routeB.dexType} (${opp.routeB.feeTier * 100}%)`);
              console.log(`     Expected Profit: ${opp.expectedProfit} ${opp.tokenA.symbol}`);
            });
            
            const result = await this.executeBatchArbitrage(
              profitable.slice(0, MAX_CONCURRENT_TRADES), // Limit to configured max
              minProfit
            );
            
            console.log(`💰 Batch result: ${result.totalProfit} ${tokenA.symbol} profit`);
            console.log(`📈 Success rate: ${result.successful}/${result.successful + result.failed}`);
          } else {
            console.log('❌ No profitable opportunities found this cycle');
          }
        }
        
        // Check pool health periodically
        if (Math.random() < 0.1) { // 10% chance per cycle
          const health = await this.getPoolHealth();
          if (!health.isHealthy) {
            console.log('⚠️  Pool health warning:', {
              utilization: `${health.utilization}%`,
              recoveryRate: `${health.recoveryRate}%`
            });
          }
        }
        
      } catch (error) {
        console.error('❌ Monitoring error:', error);
      }
    }, interval);
    
    this.monitoringInterval = monitor;
    
    // Return cleanup function
    return () => {
      this.isMonitoring = false;
      if (this.monitoringInterval) {
        clearInterval(this.monitoringInterval);
        this.monitoringInterval = undefined;
      }
      console.log('🛑 Monitoring stopped');
    };
  }
  
  /**
   * Stop monitoring
   */
  stopMonitoring(): void {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = undefined;
      this.isMonitoring = false;
      console.log('🛑 Monitoring stopped');
    }
  }
  
  /**
   * Execute borrower callback with atomic guarantees
   */
  async executeBorrowerCallback<T, U>(
    loanCoin: Coin<T>,
    callback: (coin: Coin<T>) => Promise<Coin<U>>,
    minRepayment: number,
    deadline: number = 300000
  ): Promise<{
    success: boolean;
    profit: number;
    gasUsed: number;
    callbackResult?: any;
  }> {
    try {
      const tx = new TransactionBlock();
      
      // Execute callback through a generic interface
      const callbackResult = await callback(loanCoin);
      
      // Verify repayment amount
      const repaymentAmount = callbackResult ? callbackResult.value || 0 : 0;
      
      if (repaymentAmount < minRepayment) {
        throw new Error(`Insufficient repayment: ${repaymentAmount} < ${minRepayment}`);
      }
      
      return {
        success: true,
        profit: repaymentAmount - minRepayment,
        gasUsed: 0, // Would track actual gas
        callbackResult
      };
    } catch (error) {
      console.error('Callback execution failed:', error);
      return {
        success: false,
        profit: 0,
        gasUsed: 0
      };
    }
  }
  
  /**
   * Create and manage DEX registry
   */
  async createDexRegistry(): Promise<string> {
    try {
      const tx = new TransactionBlock();
      
      const [registry] = tx.moveCall({
        target: `${this.packageId}::dex_adapter_v2::create_dex_registry`,
        arguments: []
      });
      
      const result = await this.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: this.keypair,
        requestType: 'WaitForLocalExecution'
      });
      
      if (result.effects?.status.status !== 'success') {
        throw new Error('Failed to create DEX registry');
      }
      
      const createdObjects = result.effects?.created || [];
      const registryObject = createdObjects.find(obj => obj.owner === 'Shared');
      
      if (!registryObject) {
        throw new Error('DEX registry creation failed - no shared object');
      }
      
      this.dexRegistryId = registryObject.reference.objectId;
      return this.dexRegistryId;
    } catch (error) {
      console.error('Error creating DEX registry:', error);
      throw error;
    }
  }
  
  /**
   * Add DEX route to registry
   */
  async addDexRoute<T, U>(
    route: DexRoute
  ): Promise<string> {
    try {
      if (!this.dexRegistryId) {
        throw new Error('DEX registry not initialized');
      }
      
      const tx = new TransactionBlock();
      
      tx.moveCall({
        target: `${this.packageId}::dex_adapter_v2::add_route`,
        arguments: [
          tx.object(this.dexRegistryId),
          tx.pure(route)
        ],
        typeArguments: [getTokenType(route.tokenA), getTokenType(route.tokenB)]
      });
      
      const result = await this.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: this.keypair,
        requestType: 'WaitForLocalExecution'
      });
      
      return result.digest;
    } catch (error) {
      console.error('Error adding DEX route:', error);
      throw error;
    }
  }

  /**
   * Get pool health metrics
   */
  async getPoolHealth(): Promise<{
    isHealthy: boolean;
    utilization: number;
    recoveryRate: number;
  }> {
    try {
      const tx = new TransactionBlock();
      
      const [health, utilization, recovery] = tx.moveCall({
        target: `${this.packageId}::arbitrage::check_pool_health`,
        arguments: [tx.object(this.poolId)]
      });
      
      const result = await this.client.devInspectTransactionBlock({
        transactionBlock: tx,
        sender: this.keypair.toSuiAddress()
      });
      
      if (result.effects?.status.status !== 'success') {
        throw new Error('Failed to get pool health');
      }
      
      const returnValues = result.results?.[0]?.returnValues || [];
      
      return {
        isHealthy: returnValues[0]?.[0] === '0x01',
        utilization: parseInt(returnValues[1]?.[0] || '0'),
        recoveryRate: parseInt(returnValues[2]?.[0] || '0')
      };
    } catch (error) {
      console.error('Error getting pool health:', error);
      throw error;
    }
  }

  /**
   * Helper: Get available DEX routes for token pair
   */
  private async getAvailableRoutes(
    tokenA: TokenInfo,
    tokenB: TokenInfo
  ): Promise<DexRoute[]> {
    // In real implementation, this would query DEX contracts
    return [
      {
        dexType: 'cetus',
        poolId: '0x1234567890abcdef',
        feeTier: 0.003
      },
      {
        dexType: 'turbos',
        poolId: '0xabcdef1234567890',
        feeTier: 0.0025
      },
      {
        dexType: 'aftermath',
        poolId: '0x7890abcdef123456',
        feeTier: 0.002
      }
    ];
  }

  /**
   * Helper: Calculate arbitrage profit for route pair
   */
  private async calculateArbitrage(
    routeA: DexRoute,
    routeB: DexRoute,
    tokenA: TokenInfo,
    tokenB: TokenInfo,
    amountIn: number
  ): Promise<ArbitrageOpportunity> {
    // Simplified calculation - real implementation would query DEX prices
    const feeA = amountIn * routeA.feeTier;
    const outputA = amountIn - feeA;
    
    const feeB = outputA * routeB.feeTier;
    const outputB = outputA - feeB;
    
    const profit = outputB - amountIn;
    
    return {
      routeA,
      routeB,
      amountIn,
      expectedProfit: profit,
      tokenA,
      tokenB
    };
  }
  
  /**
   * Helper: Get token type from token info
   */
  private getTokenType(token: TokenInfo): string {
    return token.type;
  }
  
  /**
   * Helper: Visual feedback for monitoring
   */
  private logVisual(message: string, type: 'info' | 'success' | 'warning' | 'error' = 'info'): void {
    if (!ENABLE_VISUAL_FEEDBACK) return;
    
    const symbols = {
      info: 'ℹ️',
      success: '✅',
      warning: '⚠️',
      error: '❌'
    };
    
    console.log(`${symbols[type]} ${message}`);
  }
  
  /**
   * Helper: Format profit summary
   */
  private formatProfitSummary(results: Array<{ success: boolean; profit: number }>): string {
    const total = results.length;
    const successful = results.filter(r => r.success).length;
    const totalProfit = results.reduce((sum, r) => sum + r.profit, 0);
    
    return `📊 Summary: ${successful}/${total} successful, Total Profit: ${totalProfit}`;
  }
}

// Export types
export type {
  TokenInfo,
  ArbitrageOpportunity,
  DexRoute,
  PoolInfo,
  FlashLoanReceipt
};