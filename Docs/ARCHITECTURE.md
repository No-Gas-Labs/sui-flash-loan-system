# Flash Loan System Architecture

## Overview
This document describes the architecture of the Flash Loan System for Sui blockchain, including on-chain and off-chain components, the Hot Potato pattern implementation, and data flow.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flash Loan System                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────┐         ┌───────────────────────┐    │
│  │   Off-Chain Layer   │         │   On-Chain Layer      │    │
│  │                     │         │                       │    │
│  │  ┌─────────────┐    │         │  ┌─────────────────┐ │    │
│  │  │   Monitor   │    │         │  │  Arbitrage      │ │    │
│  │  │   Engine    │    │         │  │  Module         │ │    │
│  │  └─────┬───────┘    │         │  └────────┬────────┘ │    │
│  │        │            │         │           │          │    │
│  │  ┌─────┴───────┐    │         │  ┌────────┴────────┐ │    │
│  │  │  Orchestrator│◄───┼─────────┼──┤  DEX Adapter  │ │    │
│  │  │    (TS)     │    │         │  │   Module      │ │    │
│  │  └─────┬───────┘    │         │  └────────┬────────┘ │    │
│  │        │            │         │           │          │    │
│  │  ┌─────┴───────┐    │         │  ┌────────┴────────┐ │    │
│  │  │   Config    │    │         │  │   Pool V2       │ │    │
│  │  │   Manager   │    │         │  │   Module        │ │    │
│  │  └─────────────┘    │         │  └─────────────────┘ │    │
│  │                     │         │                       │    │
│  └─────────────────────┘         └───────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                    Hot Potato Pattern                    │  │
│  │                                                          │  │
│  │  User Request → FlashLoanReceipt → Arbitrage → Repay    │  │
│  │        │              │              │         │         │  │
│  │        └──────────────┼──────────────┼─────────┘         │  │
│  │                       │              │                   │  │
│  │  [Cannot be dropped]  │              │                   │  │
│  │  [Must be consumed]   │              │                   │  │
│  │                       │              │                   │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### On-Chain Layer (Move Contracts)

#### 1. Pool V2 Module (`pool_v2.move`)
```
┌─────────────────────────────────────┐
│            Pool V2                  │
├─────────────────────────────────────┤
│ Functions:                          │
│ ├── create_pool()                   │
│ ├── deposit()                       │
│ ├── withdraw()                      │
│ ├── borrow()                        │
│ ├── repay()                         │
│ └── view functions                  │
├─────────────────────────────────────┤
│ Data Structures:                    │
│ ├── Pool<T>                         │
│ ├── FlashLoanReceipt<T>             │
│ └── Events                          │
└─────────────────────────────────────┘
```

#### 2. DEX Adapter V2 Module (`dex_adapter_v2.move`)
```
┌─────────────────────────────────────┐
│         DEX Adapter V2             │
├─────────────────────────────────────┤
│ Supported DEXs:                     │
│ ├── Cetus                           │
│ ├── Turbos                          │
│ └── Aftermath                       │
├─────────────────────────────────────┤
│ Functions:                          │
│ ├── swap_exact_tokens_for_tokens() │
│ ├── get_optimal_route()            │
│ ├── calculate_arbitrage_profit()   │
│ └── get_available_routes()         │
└─────────────────────────────────────┘
```

#### 3. Arbitrage Module (`arbitrage.move`)
```
┌─────────────────────────────────────┐
│           Arbitrage                 │
├─────────────────────────────────────┤
│ Functions:                          │
│ ├── execute_arbitrage()            │
│ ├── find_best_opportunity()        │
│ ├── execute_batch_arbitrage()      │
│ └── check_pool_health()            │
├─────────────────────────────────────┤
│ Events:                             │
│ ├── ArbitrageExecuted              │
│ └── ArbitrageFailed                │
└─────────────────────────────────────┘
```

### Off-Chain Layer (TypeScript)

#### 1. FlashLoanOrchestrator (`orchestrator.ts`)
```
┌─────────────────────────────────────┐
│      FlashLoanOrchestrator         │
├─────────────────────────────────────┤
│ Core Methods:                       │
│ ├── getPoolInfo()                  │
│ ├── createPool()                   │
│ ├── depositLiquidity()             │
│ ├── findArbitrageOpportunities()   │
│ ├── executeArbitrage()             │
│ ├── executeBatchArbitrage()        │
│ └── startMonitoring()              │
├─────────────────────────────────────┤
│ Monitoring:                         │
│ ├── Continuous opportunity scan    │
│ ├── Risk management                │
│ └── Profit optimization            │
└─────────────────────────────────────┘
```

## Hot Potato Pattern Implementation

The Hot Potato pattern ensures atomic execution of flash loans:

```
User Request
    │
    │  [1] borrow()
    ▼
┌─────────────────┐
│ FlashLoanReceipt │  ← Cannot be dropped
│                 │     Must be consumed
│ - pool_id       │     by repay()
│ - loan_id       │
│ - amount        │
│ - fee           │
└────────┬────────┘
         │
         │  [2] Execute arbitrage
         ▼
┌─────────────────┐
│   Arbitrage     │
│   Execution     │
└────────┬────────┘
         │
         │  [3] repay()
         ▼
    Transaction
    Complete
```

## Data Flow

### Flash Loan Execution Flow
```
1. User/Off-chain → borrow() → Pool V2
2. Pool V2 → FlashLoanReceipt → User/Off-chain
3. User/Off-chain → execute_arbitrage() → DEX Adapter
4. DEX Adapter → TradeResult → User/Off-chain
5. User/Off-chain → repay() → Pool V2
6. Pool V2 → Events → Blockchain
```

### Arbitrage Detection Flow
```
Off-chain Monitoring
    │
    ├─── Scan DEX prices
    ├─── Calculate arbitrage opportunities
    ├─── Filter by profit threshold
    ├─── Execute via flash loan
    └─── Monitor results
```

## Security Considerations

### 1. Hot Potato Pattern
- Ensures flash loans are always repaid
- Prevents loan tokens from being dropped
- Atomic execution guarantee

### 2. Access Control
- Only pool admin can withdraw liquidity
- Borrower must repay to same pool
- Fee rate validation (max 10%)

### 3. Slippage Protection
- Minimum output amounts
- Transaction deadlines
- Slippage tolerance settings

### 4. Pool Health Monitoring
- Utilization rate tracking
- Recovery rate calculation
- Health status reporting

## Gas Optimization

### 1. Move Contracts
- Efficient balance operations
- Minimal storage reads/writes
- Optimized route calculations

### 2. TypeScript Layer
- Batch transaction execution
- Efficient API calls
- Caching strategies

## Deployment Architecture

```
Development → Testnet → Mainnet
     │           │          │
     │           │          │
  Local tests  Integration  Production
  Unit tests   tests        monitoring
```

## Monitoring and Alerting

```
┌─────────────────┐
│   Monitoring    │
├─────────────────┤
│ ├── Pool health │
│ ├── Profits     │
│ ├── Failures    │
│ └── Gas usage   │
└─────────────────┘
```

## Integration Points

### 1. DEX Integration
- Cetus DEX
- Turbos DEX
- Aftermath DEX

### 2. Oracle Integration
- Price feeds
- Rate updates
- Market data

### 3. Analytics
- Profit tracking
- Performance metrics
- Risk assessment

## Configuration

### Environment Variables
- `SUI_NETWORK`: Network selection
- `PRIVATE_KEY`: Wallet authentication
- `PACKAGE_ID`: Contract package
- `POOL_OBJECT_ID`: Pool identifier

### Token Configuration
- SUI: Native token
- USDC: Stablecoin
- USDT: Stablecoin
- Custom tokens supported
```

## Quick Start

1. **Build Contracts**
   ```bash
   sui move build
   ```

2. **Run Tests**
   ```bash
   sui move test
   npm test
   ```

3. **Deploy**
   ```bash
   ./scripts/deploy.sh deploy
   ```

4. **Monitor**
   ```bash
   npm start
   ```