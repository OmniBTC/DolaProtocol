#[test_only]
module lending::logic_tests {
    use std::ascii::string;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::types::{create_dola_address, DolaAddress};
    use lending::logic;
    use lending::math::{ray_mul, ray_div};
    use lending::storage::{Self, Storage};
    use oracle::oracle::{Self, PriceOracle, OracleCap};
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::test_scenario::{Self, Scenario};
    use sui::tx_context::TxContext;

    const RAY: u64 = 100000000;

    const U64_MAX: u64 = 0xFFFFFFFFFFFFFFFF;

    /// HF 1.25
    const TARGET_HEALTH_FACTOR: u64 = 125000000;

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
    const BTC_POOL_ID: u16 = 0;

    /// 0.8
    const BTC_CF: u64 = 80000000;

    /// 1.2
    const BTC_BF: u64 = 120000000;

    /// 1
    const USDT_POOL_ID: u16 = 1;

    /// 0.95
    const USDT_CF: u64 = 95000000;

    /// 1.05
    const USDT_BF: u64 = 105000000;

    /// 2
    const USDC_POOL_ID: u16 = 2;

    /// 0.98
    const USDC_CF: u64 = 98000000;

    /// 1.01
    const USDC_BF: u64 = 101000000;

    /// 3
    const ETH_POOL_ID: u16 = 3;

    /// 0.9
    const ETH_CF: u64 = 90000000;

    /// 1.1
    const ETH_BF: u64 = 110000000;


    public fun init(ctx: &mut TxContext) {
        oracle::init_for_testing(ctx);
        app_manager::init_for_testing(ctx);
        pool_manager::init_for_testing(ctx);
        storage::init_for_testing(ctx);
    }

    public fun init_oracle(cap: &OracleCap, oracle: &mut PriceOracle) {
        // register btc oracle
        oracle::register_token_price(cap, oracle, 0, BTC_POOL_ID, 2000000, 2);

        // register usdt oracle
        oracle::register_token_price(cap, oracle, 0, USDT_POOL_ID, 100, 2);

        // register usdc oracle
        oracle::register_token_price(cap, oracle, 0, USDC_POOL_ID, 100, 2);

        // register eth oracle
        oracle::register_token_price(cap, oracle, 0, ETH_POOL_ID, 150000, 2);
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
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, BTC_POOL_ID, ctx);

        // register usdt pool
        let pool = create_dola_address(0, b"USDT");
        let pool_name = string(b"USDT");
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, USDT_POOL_ID, ctx);

        // register usdc pool
        let pool = create_dola_address(0, b"USDC");
        let pool_name = string(b"USDC");
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, USDC_POOL_ID, ctx);

        // register eth pool
        let pool = create_dola_address(0, b"ETH");
        let pool_name = string(b"ETH");
        pool_manager::register_pool(&cap, pool_manager_info, pool, pool_name, ETH_POOL_ID, ctx);
    }

    public fun init_reserves(storage: &mut Storage, oracle: &mut PriceOracle, ctx: &mut TxContext) {
        let cap = storage::register_storage_cap_for_testing();
        // register btc reserve
        storage::register_new_reserve(
            &cap,
            storage,
            oracle,
            BTC_POOL_ID,
            U64_MAX,
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
            USDT_POOL_ID,
            U64_MAX,
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
            USDC_POOL_ID,
            U64_MAX,
            TREASURY_FACTOR,
            USDC_CF,
            USDC_BF,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );

        // register eth reserve
        storage::register_new_reserve(
            &cap,
            storage,
            oracle,
            ETH_POOL_ID,
            U64_MAX,
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

    public fun init_test_scenario(creator: address): Scenario {
        let scenario_val = test_scenario::begin(creator);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, creator);
        {
            let cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            init_oracle(&cap, &mut oracle);

            test_scenario::return_to_sender(scenario, cap);
            test_scenario::return_shared(oracle);
        };
        test_scenario::next_tx(scenario, creator);
        {
            let storage = test_scenario::take_shared<Storage>(scenario);
            let total_app_info = test_scenario::take_shared<TotalAppInfo>(scenario);

            init_app(&mut storage, &mut total_app_info, test_scenario::ctx(scenario));

            test_scenario::return_shared(storage);
            test_scenario::return_shared(total_app_info);
        };
        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            init_pools(&mut pool_manager_info, test_scenario::ctx(scenario));
            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, creator);
        {
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            init_reserves(&mut storage, &mut oracle, test_scenario::ctx(scenario));

            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
        };
        (scenario_val)
    }

    public fun supply_scenario(
        scenario: &mut Scenario,
        creator: address,
        supply_pool: DolaAddress,
        supply_pool_id: u16,
        supply_user_id: u64,
        supply_amount: u64
    ) {
        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                supply_pool,
                0,
                supply_amount,
                test_scenario::ctx(scenario)
            );
            logic::execute_supply(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                supply_user_id,
                supply_pool_id,
                supply_amount
            );
            // todo: check more details
            // check user otoken
            assert!(logic::user_collateral_balance(&mut storage, supply_user_id, supply_pool_id) == supply_amount, 101);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
        };
    }

    public fun borrow_scenario(
        scenario: &mut Scenario,
        creator: address,
        borrow_pool: DolaAddress,
        borrow_pool_id: u16,
        borrow_user_id: u64,
        borrow_amount: u64
    ) {
        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            // User 0 borrow 5000 usdt
            logic::execute_borrow(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                borrow_user_id,
                borrow_pool_id,
                borrow_amount
            );
            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                borrow_pool,
                0,
                borrow_amount
            );

            // Check user dtoken
            assert!(logic::user_loan_balance(&mut storage, borrow_user_id, borrow_pool_id) == borrow_amount, 103);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
        };
    }

    #[test]
    public fun test_execute_supply() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let btc_pool = create_dola_address(0, b"BTC");
        let supply_pool = btc_pool;
        let supply_pool_id = BTC_POOL_ID;
        let supply_user_id = 0;
        let supply_amount = RAY;
        supply_scenario(
            scenario,
            creator,
            supply_pool,
            supply_pool_id,
            supply_user_id,
            supply_amount
        );

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_withdraw() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let supply_amount = RAY;
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let withdraw_amount = RAY / 2;

            // Withdraw
            logic::execute_withdraw(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                0,
                BTC_POOL_ID,
                withdraw_amount
            );
            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                btc_pool,
                0,
                withdraw_amount
            );

            // Check user otoken
            assert!(
                logic::user_collateral_balance(&mut storage, 0, BTC_POOL_ID) == (supply_amount - withdraw_amount),
                102
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_borrow() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let usdt_pool = create_dola_address(0, b"USDT");
        let supply_btc_amount = RAY;
        let supply_usdt_amount = 10000 * RAY;
        let borrow_usdt_amount = 5000 * RAY;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_repay() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let usdt_pool = create_dola_address(0, b"USDT");
        let supply_btc_amount = RAY;
        let supply_usdt_amount = 10000 * RAY;
        let borrow_usdt_amount = 5000 * RAY;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            let repay_usdt_amount = 1000 * RAY;

            // User 0 repay 1000 usdt
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                usdt_pool,
                0,
                repay_usdt_amount,
                test_scenario::ctx(scenario)
            );
            logic::execute_repay(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                0,
                USDT_POOL_ID,
                repay_usdt_amount
            );

            // Check user dtoken
            assert!(
                logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID) == (borrow_usdt_amount - repay_usdt_amount),
                104
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_liquidate() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let usdt_pool = create_dola_address(0, b"USDT");
        let supply_btc_amount = RAY;
        let supply_usdt_amount = 50000 * RAY;

        let user_btc_value = 20000 * RAY;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = ray_div(ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 0 borrow max usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            // Check user HF == 1
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) == RAY, 104);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1999900);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0
            let (_, max_liquidable_debt) = logic::calculate_max_liquidation(
                &mut storage,
                &mut oracle,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID,
                max_liquidable_debt
            );

            assert!(
                logic::user_health_factor(&mut storage, &mut oracle, 0) * 100 / RAY == TARGET_HEALTH_FACTOR * 100 / RAY,
                106
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_1() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let eth_pool = create_dola_address(0, b"ETH");
        let usdt_pool = create_dola_address(0, b"USDT");
        let usdc_pool = create_dola_address(0, b"USDC");
        let supply_btc_amount = RAY;
        let supply_eth_amount = RAY;
        let supply_usdt_amount = 50000 * RAY;
        let supply_usdc_amount = 50000 * RAY;

        let user_btc_value = 20000 * RAY;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = ray_div(ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * RAY;
        let borrow_usdc_value = ray_div(ray_mul(user_eth_value, ETH_CF), USDC_BF);
        let borrow_usdc_amount = borrow_usdc_value;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 0 supply 1 eth
        supply_scenario(scenario, creator, eth_pool, ETH_POOL_ID, 0, supply_eth_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 1 supply 50000 usdc
        supply_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 1, supply_usdc_amount);

        // User 0 borrow usdt with all btc
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdt debt to get btc
            let (_, max_liquidable_debt) = logic::calculate_max_liquidation(
                &mut storage,
                &mut oracle,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID,
                max_liquidable_debt
            );

            assert!(
                logic::user_health_factor(&mut storage, &mut oracle, 0) * 100 / RAY == TARGET_HEALTH_FACTOR * 100 / RAY,
                106
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_2() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let eth_pool = create_dola_address(0, b"ETH");
        let usdt_pool = create_dola_address(0, b"USDT");
        let usdc_pool = create_dola_address(0, b"USDC");
        let supply_btc_amount = RAY;
        let supply_eth_amount = RAY;
        let supply_usdt_amount = 50000 * RAY;
        let supply_usdc_amount = 50000 * RAY;

        let user_btc_value = 20000 * RAY;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = ray_div(ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * RAY;
        let borrow_usdc_value = ray_div(ray_mul(user_eth_value, ETH_CF), USDC_BF);
        let borrow_usdc_amount = borrow_usdc_value;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 0 supply 1 eth
        supply_scenario(scenario, creator, eth_pool, ETH_POOL_ID, 0, supply_eth_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 1 supply 50000 usdc
        supply_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 1, supply_usdc_amount);

        // User 0 borrow usdt with all btc
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdt debt to get eth
            let (_, max_liquidable_debt) = logic::calculate_max_liquidation(
                &mut storage,
                &mut oracle,
                1,
                0,
                ETH_POOL_ID,
                USDT_POOL_ID
            );

            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                1,
                0,
                ETH_POOL_ID,
                USDT_POOL_ID,
                max_liquidable_debt
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_3() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let eth_pool = create_dola_address(0, b"ETH");
        let usdt_pool = create_dola_address(0, b"USDT");
        let usdc_pool = create_dola_address(0, b"USDC");
        let supply_btc_amount = RAY;
        let supply_eth_amount = RAY;
        let supply_usdt_amount = 50000 * RAY;
        let supply_usdc_amount = 50000 * RAY;

        let user_btc_value = 20000 * RAY;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = ray_div(ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * RAY;
        let borrow_usdc_value = ray_div(ray_mul(user_eth_value, ETH_CF), USDC_BF);
        let borrow_usdc_amount = borrow_usdc_value;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 0 supply 1 eth
        supply_scenario(scenario, creator, eth_pool, ETH_POOL_ID, 0, supply_eth_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 1 supply 50000 usdc
        supply_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 1, supply_usdc_amount);

        // User 0 borrow usdt with all btc
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdc debt to get btc
            let (_, max_liquidable_debt) = logic::calculate_max_liquidation(
                &mut storage,
                &mut oracle,
                1,
                0,
                BTC_POOL_ID,
                USDC_POOL_ID
            );

            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                1,
                0,
                BTC_POOL_ID,
                USDC_POOL_ID,
                max_liquidable_debt
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_4() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = create_dola_address(0, b"BTC");
        let eth_pool = create_dola_address(0, b"ETH");
        let usdt_pool = create_dola_address(0, b"USDT");
        let usdc_pool = create_dola_address(0, b"USDC");
        let supply_btc_amount = RAY;
        let supply_eth_amount = RAY;
        let supply_usdt_amount = 50000 * RAY;
        let supply_usdc_amount = 50000 * RAY;

        let user_btc_value = 20000 * RAY;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = ray_div(ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * RAY;
        let borrow_usdc_value = ray_div(ray_mul(user_eth_value, ETH_CF), USDC_BF);
        let borrow_usdc_amount = borrow_usdc_value;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 0 supply 1 eth
        supply_scenario(scenario, creator, eth_pool, ETH_POOL_ID, 0, supply_eth_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 1 supply 50000 usdc
        supply_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 1, supply_usdc_amount);

        // User 0 borrow usdt with all btc
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdc debt to get eth
            let (_, max_liquidable_debt) = logic::calculate_max_liquidation(
                &mut storage,
                &mut oracle,
                1,
                0,
                ETH_POOL_ID,
                USDC_POOL_ID
            );

            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                1,
                0,
                ETH_POOL_ID,
                USDC_POOL_ID,
                max_liquidable_debt
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }
}
