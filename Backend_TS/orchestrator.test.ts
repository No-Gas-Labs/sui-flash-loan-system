import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import { FlashLoanOrchestrator } from './orchestrator';
import { SuiClient } from '@mysten/sui.js/client';

// Mock the SuiClient
jest.mock('@mysten/sui.js/client', () => ({
  SuiClient: jest.fn().mockImplementation(() => ({
    getObject: jest.fn(),
    signAndExecuteTransactionBlock: jest.fn(),
    devInspectTransactionBlock: jest.fn()
  })),
  getFullnodeUrl: jest.fn().mockReturnValue('https://testnet.sui.io'),
  Ed25519Keypair: {
    fromSecretKey: jest.fn().mockReturnValue({
      toSuiAddress: jest.fn().mockReturnValue('0x123')
    })
  },
  TransactionBlock: jest.fn().mockImplementation(() => ({
    splitCoins: jest.fn().mockReturnValue(['coin']),
    moveCall: jest.fn().mockReturnValue(['result']),
    pure: jest.fn().mockImplementation((value) => value),
    object: jest.fn().mockImplementation((id) => id)
  }))
}));

describe('FlashLoanOrchestrator', () => {
  let orchestrator: FlashLoanOrchestrator;
  let mockClient: jest.Mocked<SuiClient>;

  beforeEach(() => {
    orchestrator = new FlashLoanOrchestrator('testnet', 'package123', 'pool123', 'dexRegistry123', 'assetRegistry123');
    mockClient = orchestrator['client'] as jest.Mocked<SuiClient>;
  });

  afterEach(() => {
    jest.clearAllMocks();
    orchestrator.stopMonitoring(); // Clean up any monitoring
  });

  describe('Pool Management', () => {
    it('should create a new pool', async () => {
      const mockResult = {
        effects: {
          status: { status: 'success' },
          created: [{
            owner: 'Shared',
            reference: { objectId: 'new-pool-id' }
          }]
        },
        digest: 'tx123'
      };

      mockClient.signAndExecuteTransactionBlock.mockResolvedValue(mockResult as any);

      const poolId = await orchestrator.createPool('0x2::sui::SUI', 1000000, 100);
      
      expect(poolId).toBe('new-pool-id');
      expect(mockClient.signAndExecuteTransactionBlock).toHaveBeenCalledTimes(1);
    });

    it('should get pool information', async () => {
      const mockPoolData = {
        data: {
          content: {
            fields: {
              liquidity: '1000000',
              fee_basis_points: '100',
              total_borrowed: '500000',
              total_repaid: '450000',
              active_loans: '2'
            }
          }
        }
      };

      mockClient.getObject.mockResolvedValue(mockPoolData as any);

      const poolInfo = await orchestrator.getPoolInfo();
      
      expect(poolInfo).toEqual({
        liquidity: 1000000,
        feeRate: 100,
        totalBorrowed: 500000,
        totalRepaid: 450000,
        activeLoans: 2
      });
      expect(mockClient.getObject).toHaveBeenCalledWith({
        id: 'pool123',
        options: { showContent: true }
      });
    });

    it('should deposit liquidity', async () => {
      const mockResult = {
        effects: { status: { status: 'success' } },
        digest: 'tx123'
      };

      mockClient.signAndExecuteTransactionBlock.mockResolvedValue(mockResult as any);

      const txDigest = await orchestrator.depositLiquidity('0x2::sui::SUI', 500000);
      
      expect(txDigest).toBe('tx123');
      expect(mockClient.signAndExecuteTransactionBlock).toHaveBeenCalledTimes(1);
    });
  });

  describe('Arbitrage Detection', () => {
    it('should find arbitrage opportunities', async () => {
      const tokenA = {
        type: '0x2::sui::SUI',
        decimals: 9,
        symbol: 'SUI'
      };
      
      const tokenB = {
        type: '0xabc::usdc::USDC',
        decimals: 6,
        symbol: 'USDC'
      };

      const opportunities = await orchestrator.findArbitrageOpportunities(
        tokenA,
        tokenB,
        1000000
      );

      expect(Array.isArray(opportunities)).toBe(true);
      expect(opportunities.length).toBeGreaterThan(0);
      
      const firstOpportunity = opportunities[0];
      expect(firstOpportunity).toHaveProperty('routeA');
      expect(firstOpportunity).toHaveProperty('routeB');
      expect(firstOpportunity).toHaveProperty('amountIn');
      expect(firstOpportunity).toHaveProperty('expectedProfit');
    });

    it('should return empty array when no opportunities found', async () => {
      const tokenA = { type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' };
      const tokenB = { type: '0xabc::usdc::USDC', decimals: 6, symbol: 'USDC' };

      // Mock the helper methods to return no opportunities
      jest.spyOn(orchestrator as any, 'calculateArbitrage')
        .mockResolvedValue({ expectedProfit: 0 });

      const opportunities = await orchestrator.findArbitrageOpportunities(
        tokenA,
        tokenB,
        1000000
      );

      expect(opportunities).toEqual([]);
    });
  });

  describe('Arbitrage Execution', () => {
    it('should execute arbitrage successfully', async () => {
      const opportunity = {
        routeA: {
          dexType: 'cetus' as const,
          poolId: 'pool1',
          feeTier: 0.003
        },
        routeB: {
          dexType: 'turbos' as const,
          poolId: 'pool2',
          feeTier: 0.0025
        },
        amountIn: 1000000,
        expectedProfit: 5000,
        tokenA: {
          type: '0x2::sui::SUI',
          decimals: 9,
          symbol: 'SUI'
        },
        tokenB: {
          type: '0xabc::usdc::USDC',
          decimals: 6,
          symbol: 'USDC'
        }
      };

      const mockResult = {
        effects: {
          status: { status: 'success' },
          gasUsed: { computationCost: '1000' }
        },
        digest: 'tx123'
      };

      mockClient.signAndExecuteTransactionBlock.mockResolvedValue(mockResult as any);

      const result = await orchestrator.executeArbitrage(opportunity);

      expect(result.success).toBe(true);
      expect(result.profit).toBe(5000);
      expect(result.transactionDigest).toBe('tx123');
      expect(result.gasUsed).toBe(1000);
    });

    it('should handle arbitrage execution failure', async () => {
      const opportunity = {
        routeA: {
          dexType: 'cetus' as const,
          poolId: 'pool1',
          feeTier: 0.003
        },
        routeB: {
          dexType: 'turbos' as const,
          poolId: 'pool2',
          feeTier: 0.0025
        },
        amountIn: 1000000,
        expectedProfit: 5000,
        tokenA: {
          type: '0x2::sui::SUI',
          decimals: 9,
          symbol: 'SUI'
        },
        tokenB: {
          type: '0xabc::usdc::USDC',
          decimals: 6,
          symbol: 'USDC'
        }
      };

      mockClient.signAndExecuteTransactionBlock.mockRejectedValue(
        new Error('Transaction failed')
      );

      const result = await orchestrator.executeArbitrage(opportunity);

      expect(result.success).toBe(false);
      expect(result.profit).toBe(0);
      expect(result.transactionDigest).toBe('');
      expect(result.gasUsed).toBe(0);
    });
  });

  describe('Batch Execution', () => {
    it('should execute batch arbitrage successfully', async () => {
      const opportunities = [
        {
          routeA: { dexType: 'cetus' as const, poolId: 'pool1', feeTier: 0.003 },
          routeB: { dexType: 'turbos' as const, poolId: 'pool2', feeTier: 0.0025 },
          amountIn: 1000000,
          expectedProfit: 5000,
          tokenA: { type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' },
          tokenB: { type: '0xabc::usdc::USDC', decimals: 6, symbol: 'USDC' }
        },
        {
          routeA: { dexType: 'turbos' as const, poolId: 'pool3', feeTier: 0.0025 },
          routeB: { dexType: 'aftermath' as const, poolId: 'pool4', feeTier: 0.002 },
          amountIn: 2000000,
          expectedProfit: 8000,
          tokenA: { type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' },
          tokenB: { type: '0xdef::usdt::USDT', decimals: 6, symbol: 'USDT' }
        }
      ];

      const mockResult = {
        effects: {
          status: { status: 'success' },
          gasUsed: { computationCost: '1000' }
        },
        digest: 'tx123'
      };

      mockClient.signAndExecuteTransactionBlock.mockResolvedValue(mockResult as any);

      const result = await orchestrator.executeBatchArbitrage(opportunities, 1000);

      expect(result.totalProfit).toBe(13000);
      expect(result.successful).toBe(2);
      expect(result.failed).toBe(0);
      expect(result.results).toHaveLength(2);
    });
  });

  describe('Pool Health', () => {
    it('should get pool health metrics', async () => {
      const mockResult = {
        effects: { status: { status: 'success' } },
        results: [{
          returnValues: [
            ['0x01'], // isHealthy
            ['0x50'], // utilization (80%)
            ['0x5F']  // recoveryRate (95%)
          ]
        }]
      };

      mockClient.devInspectTransactionBlock.mockResolvedValue(mockResult as any);

      const health = await orchestrator.getPoolHealth();

      expect(health).toEqual({
        isHealthy: true,
        utilization: 80,
        recoveryRate: 95
      });
    });
  });

  describe('Monitoring', () => {
    it('should start and stop monitoring', async () => {
      const stopMonitoring = await orchestrator.startMonitoring(
        [
          [{ type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' },
           { type: '0xabc::usdc::USDC', decimals: 6, symbol: 'USDC' }]
        ],
        1000000,
        1000,
        100 // Fast interval for testing
      );

      expect(typeof stopMonitoring).toBe('function');
      
      stopMonitoring();
      
      // Verify monitoring is stopped
      expect(orchestrator['isMonitoring']).toBe(false);
    });

    it('should handle monitoring errors gracefully', async () => {
      const mockFindOpportunities = jest.spyOn(orchestrator as any, 'findArbitrageOpportunities')
        .mockRejectedValue(new Error('Network error'));

      const stopMonitoring = await orchestrator.startMonitoring(
        [
          [{ type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' },
           { type: '0xabc::usdc::USDC', decimals: 6, symbol: 'USDC' }]
        ],
        1000000,
        1000,
        100
      );

      // Allow some time for monitoring to run
      await new Promise(resolve => setTimeout(resolve, 200));
      
      stopMonitoring();
      mockFindOpportunities.mockRestore();
      
      // Should not throw
      expect(true).toBe(true);
    });
  });

  describe('Callback Execution', () => {
    it('should execute borrower callback successfully', async () => {
      const mockCallback = jest.fn().mockResolvedValue({ value: 1050000 });
      
      const result = await orchestrator.executeBorrowerCallback(
        { type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' } as any,
        mockCallback,
        1000000,
        300000
      );

      expect(result.success).toBe(true);
      expect(result.profit).toBe(50000);
      expect(mockCallback).toHaveBeenCalled();
    });

    it('should handle callback failures', async () => {
      const mockCallback = jest.fn().mockRejectedValue(new Error('Callback failed'));
      
      const result = await orchestrator.executeBorrowerCallback(
        { type: '0x2::sui::SUI', decimals: 9, symbol: 'SUI' } as any,
        mockCallback,
        1000000,
        300000
      );

      expect(result.success).toBe(false);
      expect(result.profit).toBe(0);
    });
  });

  describe('DEX Registry', () => {
    it('should create DEX registry', async () => {
      const mockResult = {
        effects: {
          status: { status: 'success' },
          created: [{ owner: 'Shared', reference: { objectId: 'new-registry-id' } }]
        },
        digest: 'tx123'
      };

      mockClient.signAndExecuteTransactionBlock.mockResolvedValue(mockResult as any);

      const registryId = await orchestrator.createDexRegistry();
      
      expect(registryId).toBe('new-registry-id');
      expect(orchestrator['dexRegistryId']).toBe('new-registry-id');
    });

    it('should add DEX route to registry', async () => {
      orchestrator['dexRegistryId'] = 'registry123';
      
      const mockResult = {
        effects: { status: { status: 'success' } },
        digest: 'tx123'
      };

      mockClient.signAndExecuteTransactionBlock.mockResolvedValue(mockResult as any);

      const route = {
        dexType: 'cetus' as const,
        poolId: 'pool123',
        feeTier: 0.003
      };

      const txDigest = await orchestrator.addDexRoute(route);
      
      expect(txDigest).toBe('tx123');
    });
  });

  describe('Error Handling', () => {
    it('should handle pool creation errors', async () => {
      mockClient.signAndExecuteTransactionBlock.mockRejectedValue(
        new Error('Network error')
      );

      await expect(
        orchestrator.createPool('0x2::sui::SUI', 1000000, 100, 5000)
      ).rejects.toThrow('Network error');
    });

    it('should handle pool info fetch errors', async () => {
      mockClient.getObject.mockRejectedValue(
        new Error('Object not found')
      );

      await expect(
        orchestrator.getPoolInfo()
      ).rejects.toThrow('Object not found');
    });
  });
});