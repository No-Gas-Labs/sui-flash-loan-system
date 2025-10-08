module flash_loan::pool_v2 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::vec_map::{Self, VecMap};
    use sui::type_name::{Self, TypeName};
    
    // Error codes
    const EInsufficientLiquidity: u64 = 1;
    const EInvalidAmount: u64 = 2;
    const EUnauthorized: u64 = 3;
    const ELoanNotRepaid: u64 = 4;
    const EInvalidFee: u64 = 5;
    const EAssetNotWhitelisted: u64 = 6;
    const EMaxLoanRatioExceeded: u64 = 7;
    const EPoolPaused: u64 = 8;
    
    // Events
    struct LoanIssued has copy, drop {
        pool_id: ID,
        borrower: address,
        amount: u64,
        fee: u64,
        loan_id: ID
    }
    
    struct LoanRepaid has copy, drop {
        pool_id: ID,
        borrower: address,
        amount: u64,
        fee: u64,
        loan_id: ID
    }
    
    struct DepositReceived has copy, drop {
        pool_id: ID,
        depositor: address,
        amount: u64
    }
    
    struct WithdrawalProcessed has copy, drop {
        pool_id: ID,
        withdrawer: address,
        amount: u64
    }
    
    struct PoolPaused has copy, drop {
        pool_id: ID,
        admin: address,
        timestamp: u64
    }
    
    struct PoolResumed has copy, drop {
        pool_id: ID,
        admin: address,
        timestamp: u64
    }
    
    // Main Pool structure with enhanced configuration
    struct Pool<phantom T> has key {
        id: UID,
        liquidity: Balance<T>,
        fee_basis_points: u64,
        total_borrowed: u64,
        total_repaid: u64,
        admin: address,
        active_loans: u64,
        max_loan_ratio: u64, // VISUAL SLIDER: Max % of pool per loan
        is_paused: bool,
    }
    
    // Asset registry for multi-asset support
    struct AssetRegistry has key {
        id: UID,
        supported_assets: VecMap<TypeName, AssetConfig>,
        total_pools: u64,
    }
    
    struct AssetConfig has copy, drop {
        is_whitelisted: bool,
        min_loan_amount: u64,
        max_loan_amount: u64,
    }
    
    // Hot Potato pattern for flash loan
    struct FlashLoanReceipt<phantom T> {
        pool_id: ID,
        loan_id: ID,
        amount: u64,
        fee: u64,
        borrower: address,
    }
    
    // Initialize a new pool with enhanced configuration
    public fun create_pool<T>(
        initial_liquidity: Coin<T>,
        fee_basis_points: u64,
        max_loan_ratio: u64,
        ctx: &mut TxContext
    ): Pool<T> {
        assert!(fee_basis_points <= 1000, EInvalidFee); // Max 10% fee
        assert!(max_loan_ratio <= 10000, EInvalidFee); // Max 100% ratio
        
        let pool = Pool<T> {
            id: object::new(ctx),
            liquidity: coin::into_balance(initial_liquidity),
            fee_basis_points,
            total_borrowed: 0,
            total_repaid: 0,
            admin: tx_context::sender(ctx),
            active_loans: 0,
            max_loan_ratio,
            is_paused: false,
        };
        
        pool
    }
    
    // Create asset registry for multi-asset support
    public fun create_asset_registry(ctx: &mut TxContext): AssetRegistry {
        AssetRegistry {
            id: object::new(ctx),
            supported_assets: vec_map::empty(),
            total_pools: 0,
        }
    }
    
    // Add asset to whitelist
    public fun add_asset<T>(
        registry: &mut AssetRegistry,
        min_loan: u64,
        max_loan: u64,
        ctx: &mut TxContext
    ) {
        let type_name = type_name::get<T>();
        let config = AssetConfig {
            is_whitelisted: true,
            min_loan_amount: min_loan,
            max_loan_amount: max_loan,
        };
        
        vec_map::insert(&mut registry.supported_assets, type_name, config);
    }
    
    // Pause pool (admin only)
    public fun pause_pool<T>(
        pool: &mut Pool<T>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == pool.admin, EUnauthorized);
        pool.is_paused = true;
        
        event::emit(PoolPaused {
            pool_id: object::id(pool),
            admin: pool.admin,
            timestamp: tx_context::timestamp_ms(ctx),
        });
    }
    
    // Resume pool (admin only)
    public fun resume_pool<T>(
        pool: &mut Pool<T>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == pool.admin, EUnauthorized);
        pool.is_paused = false;
        
        event::emit(PoolResumed {
            pool_id: object::id(pool),
            admin: pool.admin,
            timestamp: tx_context::timestamp_ms(ctx),
        });
    }
    
    // Deposit liquidity into the pool
    public fun deposit<T>(
        pool: &mut Pool<T>,
        coin: Coin<T>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&coin);
        balance::join(&mut pool.liquidity, coin::into_balance(coin));
        
        event::emit(DepositReceived {
            pool_id: object::id(pool),
            depositor: tx_context::sender(ctx),
            amount,
        });
    }
    
    // Withdraw liquidity from the pool (admin only)
    public fun withdraw<T>(
        pool: &mut Pool<T>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(tx_context::sender(ctx) == pool.admin, EUnauthorized);
        assert!(balance::value(&pool.liquidity) >= amount, EInsufficientLiquidity);
        
        let withdrawn = balance::split(&mut pool.liquidity, amount);
        
        event::emit(WithdrawalProcessed {
            pool_id: object::id(pool),
            withdrawer: tx_context::sender(ctx),
            amount,
        });
        
        coin::from_balance(withdrawn, ctx)
    }
    
    // Initiate flash loan using Hot Potato pattern with enhanced checks
    public fun borrow<T>(
        pool: &mut Pool<T>,
        amount: u64,
        ctx: &mut TxContext
    ): (Coin<T>, FlashLoanReceipt<T>) {
        assert!(!pool.is_paused, EPoolPaused);
        assert!(amount > 0, EInvalidAmount);
        assert!(balance::value(&pool.liquidity) >= amount, EInsufficientLiquidity);
        
        // Check max loan ratio
        let max_allowed = (balance::value(&pool.liquidity) * pool.max_loan_ratio) / 10000;
        assert!(amount <= max_allowed, EMaxLoanRatioExceeded);
        
        let loan_id = object::new(ctx);
        let fee = (amount * pool.fee_basis_points) / 10000;
        
        // Split liquidity for the loan
        let loan_amount = balance::split(&mut pool.liquidity, amount);
        let loan_coin = coin::from_balance(loan_amount, ctx);
        
        // Create receipt for tracking
        let receipt = FlashLoanReceipt<T> {
            pool_id: object::id(pool),
            loan_id: object::uid_to_inner(&loan_id),
            amount,
            fee,
            borrower: tx_context::sender(ctx),
        };
        
        pool.total_borrowed = pool.total_borrowed + amount;
        pool.active_loans = pool.active_loans + 1;
        
        event::emit(LoanIssued {
            pool_id: object::id(pool),
            borrower: tx_context::sender(ctx),
            amount,
            fee,
            loan_id: object::uid_to_inner(&loan_id),
        });
        
        (loan_coin, receipt)
    }
    
    // Repay flash loan and return receipt
    public fun repay<T>(
        pool: &mut Pool<T>,
        repayment: Coin<T>,
        receipt: FlashLoanReceipt<T>,
        ctx: &mut TxContext
    ) {
        let expected_repayment = receipt.amount + receipt.fee;
        assert!(coin::value(&repayment) == expected_repayment, ELoanNotRepaid);
        assert!(receipt.borrower == tx_context::sender(ctx), EUnauthorized);
        assert!(receipt.pool_id == object::id(pool), EUnauthorized);
        
        // Return liquidity to pool
        balance::join(&mut pool.liquidity, coin::into_balance(repayment));
        
        pool.total_repaid = pool.total_repaid + receipt.amount;
        pool.active_loans = pool.active_loans - 1;
        
        event::emit(LoanRepaid {
            pool_id: object::id(pool),
            borrower: receipt.borrower,
            amount: receipt.amount,
            fee: receipt.fee,
            loan_id: receipt.loan_id,
        });
        
        // Hot Potato is consumed here - receipt is dropped
        let FlashLoanReceipt { 
            pool_id: _, 
            loan_id: _, 
            amount: _, 
            fee: _, 
            borrower: _ 
        } = receipt;
    }
    
    // View functions
    public fun get_liquidity<T>(pool: &Pool<T>): u64 {
        balance::value(&pool.liquidity)
    }
    
    public fun get_fee_rate<T>(pool: &Pool<T>): u64 {
        pool.fee_basis_points
    }
    
    public fun get_total_borrowed<T>(pool: &Pool<T>): u64 {
        pool.total_borrowed
    }
    
    public fun get_total_repaid<T>(pool: &Pool<T>): u64 {
        pool.total_repaid
    }
    
    public fun get_active_loans<T>(pool: &Pool<T>): u64 {
        pool.active_loans
    }
    
    public fun get_admin<T>(pool: &Pool<T>): address {
        pool.admin
    }
    
    public fun get_max_loan_ratio<T>(pool: &Pool<T>): u64 {
        pool.max_loan_ratio
    }
    
    public fun is_pool_paused<T>(pool: &Pool<T>): bool {
        pool.is_paused
    }
    
    public fun get_utilization_rate<T>(pool: &Pool<T>): u64 {
        let liquidity = balance::value(&pool.liquidity);
        if (liquidity == 0) {
            0
        } else {
            (pool.total_borrowed * 10000) / (liquidity + pool.total_borrowed - pool.total_repaid)
        }
    }
}