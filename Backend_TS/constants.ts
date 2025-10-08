import { config } from 'dotenv';
config();

// Network Configuration
export const SUI_NETWORK = process.env.SUI_NETWORK || 'testnet';
export const SUI_RPC_URL = process.env.SUI_RPC_URL || 'https://fullnode.testnet.sui.io:443';

// Wallet Configuration
export const ADMIN_PRIVATE_KEY = process.env.PRIVATE_KEY || '';
export const WALLET_ADDRESS = process.env.WALLET_ADDRESS || '';

// Package Configuration
export const PACKAGE_ID = process.env.PACKAGE_ID || '';
export const POOL_OBJECT_ID = process.env.POOL_OBJECT_ID || '';

// DEX Configuration
export const CETUS_PACKAGE_ID = process.env.CETUS_PACKAGE_ID || '0x1eabed72c53feb3805120a081dc15963c204dc8d090a542138a50a971c76ce8a';
export const TURBOS_PACKAGE_ID = process.env.TURBOS_PACKAGE_ID || '0x91bfbc3864e4b9e8d4be8434a0a5c4d9069b3d82b3b3c3f5a0b9b3d82b3b3c3f5';
export const AFTERMATH_PACKAGE_ID = process.env.AFTERMATH_PACKAGE_ID || '0x15eda7330c8f99c30e430b4d82fd7ab2af3b4d1c8f9b3d82b3b3c3f5a0b9b3d82b3b3c3f5';

// Token Addresses
export const SUI_TOKEN = process.env.SUI_TOKEN || '0x2::sui::SUI';
export const USDC_TOKEN = process.env.USDC_TOKEN || '0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN';
export const USDT_TOKEN = process.env.USDT_TOKEN || '0xc060006111016b8a020ad5b33834984a437aaa7d3c74c18e09a95d48aceab08c::coin::COIN';

// Arbitrage Configuration
export const MIN_PROFIT_THRESHOLD = parseInt(process.env.MIN_PROFIT_THRESHOLD || '1000');
export const MAX_LOAN_AMOUNT = parseInt(process.env.MAX_LOAN_AMOUNT || '10000000');
export const SLIPPAGE_TOLERANCE = parseInt(process.env.SLIPPAGE_TOLERANCE || '50');
export const DEADLINE_SECONDS = parseInt(process.env.DEADLINE_SECONDS || '300');

// Monitoring Configuration
export const MONITORING_INTERVAL = parseInt(process.env.MONITORING_INTERVAL || '5000');
export const MAX_CONCURRENT_TRADES = parseInt(process.env.MAX_CONCURRENT_TRADES || '3');

// Logging Configuration
export const LOG_LEVEL = process.env.LOG_LEVEL || 'info';
export const LOG_FILE_PATH = process.env.LOG_FILE_PATH || './logs/arbitrage.log';

// Visual Feedback Configuration
export const ENABLE_VISUAL_FEEDBACK = process.env.ENABLE_VISUAL_FEEDBACK === 'true';
export const SHOW_PROFIT_SUMMARY = process.env.SHOW_PROFIT_SUMMARY !== 'false';
export const SHOW_POOL_HEALTH_WARNINGS = process.env.SHOW_POOL_HEALTH_WARNINGS !== 'false';

// Callback Configuration
export const DEFAULT_CALLBACK_DEADLINE = parseInt(process.env.DEFAULT_CALLBACK_DEADLINE || '300000');
export const MAX_CALLBACK_GAS = parseInt(process.env.MAX_CALLBACK_GAS || '10000000');

// Registry Configuration
export const ENABLE_DEX_REGISTRY = process.env.ENABLE_DEX_REGISTRY === 'true';
export const ENABLE_ASSET_REGISTRY = process.env.ENABLE_ASSET_REGISTRY === 'true';

// DEX Routes for testing
export const DEX_ROUTES = [
  {
    dexType: 'cetus' as const,
    poolId: '0x1234567890abcdef',
    feeTier: 0.003
  },
  {
    dexType: 'turbos' as const,
    poolId: '0xabcdef1234567890',
    feeTier: 0.0025
  },
  {
    dexType: 'aftermath' as const,
    poolId: '0x7890abcdef123456',
    feeTier: 0.002
  }
];

// Validation
export function validateConfig(): void {
  if (!ADMIN_PRIVATE_KEY) {
    throw new Error('PRIVATE_KEY environment variable is required');
  }
  
  if (!WALLET_ADDRESS) {
    throw new Error('WALLET_ADDRESS environment variable is required');
  }
  
  // Validate private key format
  if (!/^[0-9a-fA-F]{64}$/.test(ADMIN_PRIVATE_KEY)) {
    throw new Error('PRIVATE_KEY must be a 64-character hex string');
  }
  
  // Validate wallet address format
  if (!/^0x[0-9a-fA-F]{64}$/.test(WALLET_ADDRESS)) {
    throw new Error('WALLET_ADDRESS must be a 66-character hex string starting with 0x');
  }
}

// Network-specific configurations
export const NETWORK_CONFIGS = {
  mainnet: {
    rpcUrl: 'https://fullnode.mainnet.sui.io:443',
    explorerUrl: 'https://suiscan.xyz/mainnet/tx'
  },
  testnet: {
    rpcUrl: 'https://fullnode.testnet.sui.io:443',
    explorerUrl: 'https://suiscan.xyz/testnet/tx'
  },
  devnet: {
    rpcUrl: 'https://fullnode.devnet.sui.io:443',
    explorerUrl: 'https://suiscan.xyz/devnet/tx'
  },
  local: {
    rpcUrl: 'http://localhost:9000',
    explorerUrl: 'http://localhost:3000/tx'
  }
};

// Default token configurations
export const DEFAULT_TOKENS = {
  SUI: {
    type: SUI_TOKEN,
    decimals: 9,
    symbol: 'SUI'
  },
  USDC: {
    type: USDC_TOKEN,
    decimals: 6,
    symbol: 'USDC'
  },
  USDT: {
    type: USDT_TOKEN,
    decimals: 6,
    symbol: 'USDT'
  }
};

// Error messages
export const ERROR_MESSAGES = {
  INVALID_POOL_ID: 'Invalid pool ID',
  INSUFFICIENT_LIQUIDITY: 'Insufficient liquidity in pool',
  ARBITRAGE_FAILED: 'Arbitrage execution failed',
  NETWORK_ERROR: 'Network connection error',
  INVALID_PRIVATE_KEY: 'Invalid private key format',
  INVALID_WALLET_ADDRESS: 'Invalid wallet address format'
} as const;

// Event names
export const EVENT_NAMES = {
  LOAN_ISSUED: 'LoanIssued',
  LOAN_REPAID: 'LoanRepaid',
  DEPOSIT_RECEIVED: 'DepositReceived',
  WITHDRAWAL_PROCESSED: 'WithdrawalProcessed',
  ARBITRAGE_EXECUTED: 'ArbitrageExecuted',
  ARBITRAGE_FAILED: 'ArbitrageFailed'
} as const;