#[test_only]
module lending::logic_tests {
    use std::ascii::string;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::types::create_dola_address;
    use lending::storage::{Self, Storage};
    use oracle::oracle::{Self, PriceOracle};
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::test_scenario;
    use sui::tx_context::TxContext;

    const RAY: u64 = 100000000;

    /// 10%
    const TREASURY_FACTOR: u64 = 10000000;

    /// 2%
    const BASE_BORROW_RATE: u64 = 2000000;

    /// 0.07
    const BORROW_RATE_SLOPE1: u64 = 7000000;

    /// 3
    const BORROW_RATE_SLOPE2: u64 = 300000000;

    /// 45%
    const OPTIMAL_UTILIZATION: u64 = 45000000;

    /// 0
    const BTC_POOL_ID: u64 = 0;

    /// 0.8
    const BTC_CF: u64 = 80000000;

    /// 1.2
    const BTC_BF: u64 = 120000000;

    /// 1
    const USDT_POOL_ID: u64 = 1;

    /// 0.95
    const USDT_CF: u64 = 95000000;

    /// 1.05
    const USDT_BF: u64 = 105000000;

    /// 2
    const USDC_POOL_ID: u64 = 2;

    /// 0.98
    const USDC_CF: u64 = 98000000;

    /// 1.01
    const USDC_BF: u64 = 101000000;

    public fun init(ctx: &mut TxContext) {
        oracle::init_for_testing(ctx);
        app_manager::init_for_testing(ctx);
        pool_manager::init_for_testing(ctx);
        storage::init_for_testing(ctx);
    }

    public fun init_app(storage: &mut Storage, total_app_info: &mut TotalAppInfo, ctx: &mut TxContext) {
        let app_cap = app_manager::register_app_for_testing(total_app_info, ctx);
        storage::transfer_app_cap(storage, app_cap);
    }

    public fun init_pools(pool_manager_info: &mut PoolManagerInfo, ctx: &mut TxContext) {
        let cap = pool_manager::register_manager_cap_for_testing();

        // register btc pool
        let pool = create_dola_address(0, b"BTC");
        let pool_name = string(b"BTC");
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, 0, ctx);

        // register usdt pool
        let pool = create_dola_address(0, b"USDT");
        let pool_name = string(b"USDT");
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, 1, ctx);

        // register usdc pool
        let pool = create_dola_address(0, b"USDC");
        let pool_name = string(b"USDC");
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, 2, ctx);
    }

    public fun init_reserves(storage: &mut Storage, oracle: &mut PriceOracle, ctx: &mut TxContext) {
        let cap = storage::register_storage_cap_for_testing();
        // register btc reserve
        storage::register_new_reserve(
            &cap,
            storage,
            oracle,
            0,
            0,
            TREASURY_FACTOR,
            BTC_CF,
            BTC_BF,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );

        // register usdt reserve
        storage::register_new_reserve(
            &cap,
            storage,
            oracle,
            1,
            0,
            TREASURY_FACTOR,
            USDT_CF,
            USDT_BF,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );

        // register usdc reserve
        storage::register_new_reserve(
            &cap,
            storage,
            oracle,
            2,
            0,
            TREASURY_FACTOR,
            USDC_CF,
            USDC_BF,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );
    }

    #[test]
    public fun test_execute_supply() {
        let creator = @0xA;

        let scenario_val = test_scenario::begin(creator);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };
        test_scenario::end(scenario_val);
    }
}
