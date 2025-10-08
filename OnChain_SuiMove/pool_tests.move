#[test_only]
module flash_loan::pool_tests {
    use sui::test_scenario::{Self, Scenario, next_tx, ctx, take_from_address};
    use sui::coin::{Self, Coin};
    use sui::test_coin::{Self, TEST_COIN};
    use sui::object::{Self};
    use sui::tx_context::{Self};
    
    use flash_loan::pool_v2::{Self, Pool, FlashLoanReceipt};
    
    // Test constants
    const ADMIN: address = @0xA;
    const USER: address = @0xB;
    const INITIAL_LIQUIDITY: u64 = 1000000;
    const LOAN_AMOUNT: u64 = 100000;
    const FEE_BASIS_POINTS: u64 = 100; // 1%
    
    #[test]
    fun test_pool_creation() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create test coin
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(INITIAL_LIQUIDITY, test_scenario::ctx(&mut scenario));
            let pool = pool_v2::create_pool(coin, FEE_BASIS_POINTS, test_scenario::ctx(&mut scenario));
            
            assert!(pool_v2::get_liquidity(&pool) == INITIAL_LIQUIDITY, 0);
            assert!(pool_v2::get_fee_rate(&pool) == FEE_BASIS_POINTS, 1);
            assert!(pool_v2::get_admin(&pool) == ADMIN, 2);
            
            test_scenario::return_shared(pool);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_deposit_and_withdraw() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create pool with initial liquidity
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(INITIAL_LIQUIDITY, test_scenario::ctx(&mut scenario));
            let pool = pool_v2::create_pool(coin, FEE_BASIS_POINTS, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };
        
        // Deposit additional liquidity
        next_tx(&mut scenario, ADMIN);
        {
            let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
            let coin = test_coin::mint(500000, test_scenario::ctx(&mut scenario));
            
            pool_v2::deposit(&mut pool, coin, test_scenario::ctx(&mut scenario));
            assert!(pool_v2::get_liquidity(&pool) == INITIAL_LIQUIDITY + 500000, 0);
            
            test_scenario::return_shared(pool);
        };
        
        // Withdraw liquidity
        next_tx(&mut scenario, ADMIN);
        {
            let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
            let withdrawn = pool_v2::withdraw(&mut pool, 200000, test_scenario::ctx(&mut scenario));
            
            assert!(pool_v2::get_liquidity(&pool) == INITIAL_LIQUIDITY + 300000, 0);
            assert!(coin::value(&withdrawn) == 200000, 1);
            
            coin::burn_for_testing(withdrawn);
            test_scenario::return_shared(pool);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_flash_loan_borrow_and_repay() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create pool
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(INITIAL_LIQUIDITY, test_scenario::ctx(&mut scenario));
            let pool = pool_v2::create_pool(coin, FEE_BASIS_POINTS, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };
        
        // Test flash loan
        next_tx(&mut scenario, USER);
        {
            let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
            
            // Borrow flash loan
            let (loan_coin, receipt) = pool_v2::borrow(
                &mut pool, 
                LOAN_AMOUNT, 
                test_scenario::ctx(&mut scenario)
            );
            
            assert!(pool_v2::get_active_loans(&pool) == 1, 0);
            assert!(pool_v2::get_total_borrowed(&pool) == LOAN_AMOUNT, 1);
            assert!(coin::value(&loan_coin) == LOAN_AMOUNT, 2);
            
            // Calculate repayment amount
            let fee = (LOAN_AMOUNT * FEE_BASIS_POINTS) / 10000;
            let repayment_amount = LOAN_AMOUNT + fee;
            
            // Create repayment coin
            let repayment_coin = test_coin::mint(repayment_amount, test_scenario::ctx(&mut scenario));
            
            // Repay flash loan
            pool_v2::repay(
                &mut pool,
                repayment_coin,
                receipt,
                test_scenario::ctx(&mut scenario)
            );
            
            assert!(pool_v2::get_active_loans(&pool) == 0, 3);
            assert!(pool_v2::get_total_repaid(&pool) == LOAN_AMOUNT, 4);
            assert!(pool_v2::get_liquidity(&pool) == INITIAL_LIQUIDITY + fee, 5);
            
            test_scenario::return_shared(pool);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = pool_v2::EInsufficientLiquidity)]
    fun test_insufficient_liquidity() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create pool
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(1000, test_scenario::ctx(&mut scenario));
            let pool = pool_v2::create_pool(coin, FEE_BASIS_POINTS, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };
        
        // Try to borrow more than available
        next_tx(&mut scenario, USER);
        {
            let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
            let (_loan_coin, _receipt) = pool_v2::borrow(
                &mut pool, 
                2000, // More than available
                test_scenario::ctx(&mut scenario)
            );
            test_scenario::return_shared(pool);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = pool_v2::EInvalidAmount)]
    fun test_zero_amount_loan() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create pool
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(INITIAL_LIQUIDITY, test_scenario::ctx(&mut scenario));
            let pool = pool_v2::create_pool(coin, FEE_BASIS_POINTS, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };
        
        // Try to borrow zero amount
        next_tx(&mut scenario, USER);
        {
            let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
            let (_loan_coin, _receipt) = pool_v2::borrow(
                &mut pool, 
                0, // Zero amount
                test_scenario::ctx(&mut scenario)
            );
            test_scenario::return_shared(pool);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = pool_v2::EInvalidFee)]
    fun test_invalid_fee_rate() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Try to create pool with invalid fee (> 10%)
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(INITIAL_LIQUIDITY, test_scenario::ctx(&mut scenario));
            let _pool = pool_v2::create_pool(coin, 1500, test_scenario::ctx(&mut scenario)); // 15% fee
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_multiple_loans() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create pool
        next_tx(&mut scenario, ADMIN);
        {
            let coin = test_coin::mint(INITIAL_LIQUIDITY, test_scenario::ctx(&mut scenario));
            let pool = pool_v2::create_pool(coin, FEE_BASIS_POINTS, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };
        
        // Multiple users taking loans
        let users = vector[USER, @0xC, @0xD];
        let mut i = 0;
        let len = vector::length(&users);
        
        while (i < len) {
            let user = *vector::borrow(&users, i);
            
            next_tx(&mut scenario, user);
            {
                let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
                
                // Each user takes a loan
                let (loan_coin, receipt) = pool_v2::borrow(
                    &mut pool,
                    LOAN_AMOUNT,
                    test_scenario::ctx(&mut scenario)
                );
                
                let fee = (LOAN_AMOUNT * FEE_BASIS_POINTS) / 10000;
                let repayment_amount = LOAN_AMOUNT + fee;
                
                let repayment_coin = test_coin::mint(
                    repayment_amount, 
                    test_scenario::ctx(&mut scenario)
                );
                
                pool_v2::repay(
                    &mut pool,
                    repayment_coin,
                    receipt,
                    test_scenario::ctx(&mut scenario)
                );
                
                coin::burn_for_testing(loan_coin);
                test_scenario::return_shared(pool);
            };
            
            i = i + 1;
        };
        
        // Verify final state
        next_tx(&mut scenario, ADMIN);
        {
            let pool = test_scenario::take_shared<Pool<TEST_COIN>>(&mut scenario);
            let expected_fee = (LOAN_AMOUNT * FEE_BASIS_POINTS * len) / 10000;
            
            assert!(pool_v2::get_active_loans(&pool) == 0, 0);
            assert!(pool_v2::get_total_borrowed(&pool) == LOAN_AMOUNT * len, 1);
            assert!(pool_v2::get_total_repaid(&pool) == LOAN_AMOUNT * len, 2);
            assert!(pool_v2::get_liquidity(&pool) == INITIAL_LIQUIDITY + expected_fee, 3);
            
            test_scenario::return_shared(pool);
        };
        
        test_scenario::end(scenario);
    }
}