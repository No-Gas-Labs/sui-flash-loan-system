module flash_loan::arbitrage {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    
    use flash_loan::pool_v2::{Self, Pool, FlashLoanReceipt};
    use flash_loan::dex_adapter_v2::{Self, Route, TradeResult};
    
    // Error codes
    const ENoProfit: u64 = 1;
    const EInvalidRoute: u64 = 2;
    const EDeadlineExceeded: u64 = 3;
    const EInsufficientBalance: u64 = 4;
    
    // Events
    struct ArbitrageExecuted has copy, drop {
        pool_id: address,
        token_a: address,
        token_b: address,
        amount_in: u64,
        profit: u64,
        route_a: Route,
        route_b: Route,
        timestamp: u64,
    }
    
    struct ArbitrageFailed has copy, drop {
        pool_id: address,
        reason: u8,
        timestamp: u64,
    }
    
    // Arbitrage execution result
    struct ArbitrageResult {
        profit: u64,
        gas_used: u64,
        routes_used: vector<Route>,
    }
    
    // Execute arbitrage using flash loan
    public fun execute_arbitrage<T, U>(
        pool: &mut Pool<T>,
        route_a: Route,
        route_b: Route,
        loan_amount: u64,
        min_profit: u64,
        deadline: u64,
        ctx: &mut TxContext
    ): ArbitrageResult {
        // Check deadline
        let current_time = tx_context::timestamp_ms(ctx);
        assert!(current_time <= deadline, EDeadlineExceeded);
        
        // Check profit opportunity
        let expected_profit = dex_adapter_v2::calculate_arbitrage_profit(
            &route_a, &route_b, loan_amount
        );
        assert!(expected_profit >= min_profit, ENoProfit);
        
        // Get flash loan
        let (loan_coin, receipt) = pool_v2::borrow(pool, loan_amount, ctx);
        
        // Execute first swap
        let (swap_result_a, trade_a) = execute_swap_cycle::<T, U>(
            loan_coin,
            &route_a,
            ctx
        );
        
        // Execute second swap
        let (final_coin, trade_b) = execute_swap_cycle::<U, T>(
            swap_result_a,
            &route_b,
            ctx
        );
        
        // Calculate actual profit
        let final_amount = coin::value(&final_coin);
        let actual_profit = final_amount - (loan_amount + receipt.fee);
        
        if (actual_profit >= min_profit) {
            // Repay flash loan
            pool_v2::repay(pool, final_coin, receipt, ctx);
            
            // Emit success event
            event::emit(ArbitrageExecuted {
                pool_id: pool_v2::get_admin(pool),
                token_a: route_a.token_a,
                token_b: route_a.token_b,
                amount_in: loan_amount,
                profit: actual_profit,
                route_a,
                route_b,
                timestamp: current_time,
            });
            
            let mut routes = vector::empty<Route>();
            vector::push_back(&mut routes, route_a);
            vector::push_back(&mut routes, route_b);
            
            ArbitrageResult {
                profit: actual_profit,
                gas_used: 0, // Simplified - would track actual gas
                routes_used: routes,
            }
        } else {
            // Handle failure - attempt to return original tokens
            pool_v2::repay(pool, final_coin, receipt, ctx);
            
            event::emit(ArbitrageFailed {
                pool_id: pool_v2::get_admin(pool),
                reason: 1, // Profit too low
                timestamp: current_time,
            });
            
            ArbitrageResult {
                profit: 0,
                gas_used: 0,
                routes_used: vector::empty<Route>(),
            }
        }
    }
    
    // Execute a single swap cycle
    fun execute_swap_cycle<T, U>(
        input: Coin<T>,
        route: &Route,
        ctx: &mut TxContext
    ): (Coin<U>, TradeResult) {
        let params = dex_adapter_v2::SwapParams {
            route: *route,
            amount_in: coin::value(&input),
            min_amount_out: 0, // Would calculate based on slippage
            deadline: tx_context::timestamp_ms(ctx) + 60000, // 1 minute
        };
        
        dex_adapter_v2::swap_exact_tokens_for_tokens(input, params, ctx)
    }
    
    // Find best arbitrage opportunity
    public fun find_best_opportunity<T, U>(
        pool: &Pool<T>,
        available_routes: vector<Route>,
        max_amount: u64,
        min_profit: u64
    ): (Route, Route, u64, u64) {
        let best_route_a = vector::borrow(&available_routes, 0);
        let best_route_b = vector::borrow(&available_routes, 1);
        let best_amount = 0;
        let best_profit = 0;
        
        let i = 0;
        let len = vector::length(&available_routes);
        
        while (i < len) {
            let route_a = vector::borrow(&available_routes, i);
            let j = 0;
            
            while (j < len) {
                if (i != j) {
                    let route_b = vector::borrow(&available_routes, j);
                    
                    let k = 1000; // Start with small amount
                    while (k <= max_amount) {
                        let profit = dex_adapter_v2::calculate_arbitrage_profit(
                            route_a, route_b, k
                        );
                        
                        if (profit >= min_profit && profit > best_profit) {
                            best_route_a = route_a;
                            best_route_b = route_b;
                            best_amount = k;
                            best_profit = profit;
                        };
                        
                        k = k + 1000;
                    };
                };
                j = j + 1;
            };
            i = i + 1;
        };
        
        (*best_route_a, *best_route_b, best_amount, best_profit)
    }
    
    // Batch arbitrage execution
    public fun execute_batch_arbitrage<T, U>(
        pool: &mut Pool<T>,
        opportunities: vector<(Route, Route, u64)>,
        min_total_profit: u64,
        ctx: &mut TxContext
    ): vector<ArbitrageResult> {
        let results = vector::empty<ArbitrageResult>();
        let total_profit = 0;
        
        let i = 0;
        let len = vector::length(&opportunities);
        
        while (i < len) {
            let (route_a, route_b, amount) = *vector::borrow(&opportunities, i);
            
            let result = execute_arbitrage::<T, U>(
                pool,
                route_a,
                route_b,
                amount,
                0, // No minimum for batch
                tx_context::timestamp_ms(ctx) + 300000, // 5 minutes
                ctx
            );
            
            vector::push_back(&mut results, result);
            total_profit = total_profit + result.profit;
            
            i = i + 1;
        };
        
        if (total_profit >= min_total_profit) {
            results
        } else {
            vector::empty<ArbitrageResult>()
        }
    }
    
    // Risk management - check pool health
    public fun check_pool_health<T>(pool: &Pool<T>): (bool, u64, u64) {
        let liquidity = pool_v2::get_liquidity(pool);
        let borrowed = pool_v2::get_total_borrowed(pool);
        let repaid = pool_v2::get_total_repaid(pool);
        
        let utilization = if (liquidity > 0) {
            (borrowed * 100) / liquidity
        } else {
            0
        };
        
        let recovery_rate = if (borrowed > 0) {
            (repaid * 100) / borrowed
        } else {
            100
        };
        
        let is_healthy = utilization < 80 && recovery_rate >= 95;
        (is_healthy, utilization, recovery_rate)
    }
}