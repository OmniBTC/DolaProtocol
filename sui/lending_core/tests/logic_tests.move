// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

#[test_only]
module lending_core::logic_tests {
    use std::ascii;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::dola_address::{Self, DolaAddress};
    use governance::genesis;
    use lending_core::logic;
    use lending_core::storage::{Self, Storage};
    use oracle::oracle::{Self, PriceOracle, OracleCap};
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use ray_math::math;
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};
    use sui::tx_context::TxContext;

    const ONE: u256 = 100000000;

    const RAY: u256 = 1000000000000000000000000000;

    const MILLISECONDS_PER_DAY: u64 = 86400000;

    const SECONDS_PER_YEAR: u256 = 31536000;

    const LENDING_APP_ID: u16 = 1;

    const U256_MAX: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// HF 1.25
    const TARGET_HEALTH_FACTOR: u256 = 1250000000000000000000000000;

    /// 10%
    const TREASURY_FACTOR: u256 = 100000000000000000000000000;

    /// 2%
    const BASE_BORROW_RATE: u256 = 20000000000000000000000000;

    /// 0.07
    const BORROW_RATE_SLOPE1: u256 = 70000000000000000000000000;

    /// 3
    const BORROW_RATE_SLOPE2: u256 = 3000000000000000000000000000;

    /// 45%
    const OPTIMAL_UTILIZATION: u256 = 450000000000000000000000000;

    /// 0
    const BTC_POOL_ID: u16 = 0;

    /// 0.8
    const BTC_CF: u256 = 800000000000000000000000000;

    /// 1.2
    const BTC_BF: u256 = 1200000000000000000000000000;

    /// 1
    const USDT_POOL_ID: u16 = 1;

    /// 0.95
    const USDT_CF: u256 = 950000000000000000000000000;

    /// 1.05
    const USDT_BF: u256 = 1050000000000000000000000000;

    /// 2
    const USDC_POOL_ID: u16 = 2;

    /// 0.98
    const USDC_CF: u256 = 980000000000000000000000000;

    /// 1.01
    const USDC_BF: u256 = 1010000000000000000000000000;

    /// 3
    const ETH_POOL_ID: u16 = 3;

    /// 0.9
    const ETH_CF: u256 = 900000000000000000000000000;

    /// 1.1
    const ETH_BF: u256 = 1100000000000000000000000000;

    /// 4
    const ISOLATE_POOL_ID: u16 = 4;

    /// 0.7
    const ISOLATE_CF: u256 = 700000000000000000000000000;

    public fun init_for_testing(ctx: &mut TxContext) {
        oracle::init_for_testing(ctx);
        app_manager::init_for_testing(ctx);
        pool_manager::init_for_testing(ctx);
    }

    public fun init_oracle(cap: &OracleCap, oracle: &mut PriceOracle, ctx: &mut TxContext) {
        // create sui clock
        clock::create_for_testing(ctx);

        // register btc oracle
        oracle::register_token_price(cap, oracle, BTC_POOL_ID, 2000000, 2);

        // register usdt oracle
        oracle::register_token_price(cap, oracle, USDT_POOL_ID, 100, 2);

        // register usdc oracle
        oracle::register_token_price(cap, oracle, USDC_POOL_ID, 100, 2);

        // register eth oracle
        oracle::register_token_price(cap, oracle, ETH_POOL_ID, 150000, 2);

        // register isolate oracle
        oracle::register_token_price(cap, oracle, ISOLATE_POOL_ID, 10000, 2);
    }

    public fun init_app(total_app_info: &mut TotalAppInfo, ctx: &mut TxContext) {
        // app_id 0 for system core
        let app_cap = app_manager::register_app_for_testing(total_app_info, ctx);
        app_manager::destroy_app_cap(app_cap);
        // app_id 1 for lending core
        let app_cap = app_manager::register_app_for_testing(total_app_info, ctx);
        storage::init_for_testing(app_cap, ctx);
    }

    public fun init_pools(pool_manager_info: &mut PoolManagerInfo, ctx: &mut TxContext) {
        let governance_cap = genesis::register_governance_cap_for_testing();


        // register btc pool
        let pool = dola_address::create_dola_address(0, b"BTC");
        let pool_name = ascii::string(b"BTC");
        pool_manager::register_pool_id(
            &governance_cap,
            pool_manager_info,
            pool_name,
            BTC_POOL_ID,
            ctx
        );
        pool_manager::register_pool(&governance_cap, pool_manager_info, pool, BTC_POOL_ID);
        pool_manager::set_pool_weight(&governance_cap, pool_manager_info, pool, 1);

        // register usdt pool
        let pool = dola_address::create_dola_address(0, b"USDT");
        let pool_name = ascii::string(b"USDT");
        pool_manager::register_pool_id(
            &governance_cap,
            pool_manager_info,
            pool_name,
            USDT_POOL_ID,
            ctx
        );
        pool_manager::register_pool(&governance_cap, pool_manager_info, pool, USDT_POOL_ID);
        pool_manager::set_pool_weight(&governance_cap, pool_manager_info, pool, 1);

        // register usdc pool
        let pool = dola_address::create_dola_address(0, b"USDC");
        let pool_name = ascii::string(b"USDC");
        pool_manager::register_pool_id(
            &governance_cap,
            pool_manager_info,
            pool_name,
            USDC_POOL_ID,
            ctx
        );
        pool_manager::register_pool(&governance_cap, pool_manager_info, pool, USDC_POOL_ID);
        pool_manager::set_pool_weight(&governance_cap, pool_manager_info, pool, 1);

        // register eth pool
        let pool = dola_address::create_dola_address(0, b"ETH");
        let pool_name = ascii::string(b"ETH");
        pool_manager::register_pool_id(
            &governance_cap,
            pool_manager_info,
            pool_name,
            ETH_POOL_ID,
            ctx
        );
        pool_manager::register_pool(&governance_cap, pool_manager_info, pool, ETH_POOL_ID);
        pool_manager::set_pool_weight(&governance_cap, pool_manager_info, pool, 1);

        // register isolated pool
        let pool = dola_address::create_dola_address(0, b"ISOLATE");
        let pool_name = ascii::string(b"ISOLATE");
        pool_manager::register_pool_id(
            &governance_cap,
            pool_manager_info,
            pool_name,
            ISOLATE_POOL_ID,
            ctx
        );
        pool_manager::register_pool(&governance_cap, pool_manager_info, pool, ISOLATE_POOL_ID);
        pool_manager::set_pool_weight(&governance_cap, pool_manager_info, pool, 1);
        genesis::destroy(governance_cap);
    }

    public fun init_reserves(storage: &mut Storage, clock: &Clock, ctx: &mut TxContext) {
        let cap = genesis::register_governance_cap_for_testing();
        // register btc reserve
        storage::register_new_reserve(
            &cap,
            storage,
            clock,
            BTC_POOL_ID,
            false,
            false,
            666,
            TREASURY_FACTOR,
            0,
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
            clock,
            USDT_POOL_ID,
            false,
            true,
            666,
            TREASURY_FACTOR,
            0,
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
            clock,
            USDC_POOL_ID,
            false,
            true,
            666,
            TREASURY_FACTOR,
            0,
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
            clock,
            ETH_POOL_ID,
            false,
            false,
            666,
            TREASURY_FACTOR,
            0,
            ETH_CF,
            ETH_BF,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );

        // register isolated reserve
        storage::register_new_reserve(
            &cap,
            storage,
            clock,
            ISOLATE_POOL_ID,
            true,
            false,
            666,
            TREASURY_FACTOR,
            1000 * ONE,
            ISOLATE_CF,
            0,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );
        genesis::destroy(cap);
    }

    public fun init_test_scenario(creator: address): Scenario {
        let scenario_val = test_scenario::begin(creator);
        let scenario = &mut scenario_val;
        {
            init_for_testing(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, creator);
        {
            let cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);

            init_oracle(&cap, &mut oracle, test_scenario::ctx(scenario));

            test_scenario::return_to_sender(scenario, cap);
            test_scenario::return_shared(oracle);
        };
        test_scenario::next_tx(scenario, creator);
        {
            let total_app_info = test_scenario::take_shared<TotalAppInfo>(scenario);

            init_app(&mut total_app_info, test_scenario::ctx(scenario));

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
            let clock = test_scenario::take_shared<Clock>(scenario);
            init_reserves(&mut storage, &clock, test_scenario::ctx(scenario));

            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };
        (scenario_val)
    }

    public fun supply_scenario(
        scenario: &mut Scenario,
        creator: address,
        supply_pool: DolaAddress,
        supply_pool_id: u16,
        supply_user_id: u64,
        supply_amount: u256
    ) {
        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                supply_pool,
                LENDING_APP_ID,
                supply_amount,
            );
            logic::execute_supply(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id,
                supply_pool_id,
                supply_amount
            );
            // check user otoken
            assert!(logic::user_collateral_balance(&mut storage, supply_user_id, supply_pool_id) == supply_amount, 101);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
    }

    public fun borrow_scenario(
        scenario: &mut Scenario,
        creator: address,
        borrow_pool: DolaAddress,
        borrow_pool_id: u16,
        borrow_user_id: u64,
        borrow_amount: u256
    ) {
        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            // User 0 borrow 5000 usdt
            logic::execute_borrow(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                borrow_user_id,
                borrow_pool_id,
                borrow_amount
            );
            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                borrow_pool,
                LENDING_APP_ID,
                borrow_amount
            );

            // Check user dtoken
            assert!(logic::user_loan_balance(&mut storage, borrow_user_id, borrow_pool_id) == borrow_amount, 103);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
    }

    fun get_percentage(rate: u256): u256 {
        rate * 10000 / RAY
    }

    #[test]
    public fun test_cancel_as_collateral() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_pool = btc_pool;
        let supply_pool_id = BTC_POOL_ID;
        let supply_user_id = 0;
        let supply_amount = ONE;
        supply_scenario(
            scenario,
            creator,
            supply_pool,
            supply_pool_id,
            supply_user_id,
            supply_amount
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 201);
            logic::cancel_as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID
            );
            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 202);
            assert!(logic::user_health_collateral_value(&mut storage, &mut oracle, 0) == 0, 203);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ENOT_HEALTH)]
    public fun test_cancel_as_collateral_with_not_health() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 201);
            logic::cancel_as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID
            );
            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 202);
            assert!(logic::user_health_collateral_value(&mut storage, &mut oracle, 0) == 0, 203);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_cancel_as_collateral_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 201);
            assert!(logic::is_isolation_mode(&mut storage, 0), 202);
            logic::cancel_as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                ISOLATE_POOL_ID
            );
            assert!(logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 203);
            assert!(!logic::is_isolation_mode(&mut storage, 0), 204);
            assert!(logic::user_health_collateral_value(&mut storage, &mut oracle, 0) == 0, 205);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ENOT_HEALTH)]
    public fun test_cancel_as_collateral_with_not_health_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_isolate_amount = ONE;
        let supply_usdt_amount = 1000 * ONE;
        let borrow_usdt_amount = 50 * ONE;

        // User 0 supply 1 isolate
        supply_scenario(scenario, creator, isolate_pool, ISOLATE_POOL_ID, 0, supply_isolate_amount);
        // User 1 supply 1000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 50 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 201);
            logic::cancel_as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                ISOLATE_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_as_collateral() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            logic::cancel_as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                ISOLATE_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 301);
            logic::as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID
            );
            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 302);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EIN_ISOLATION)]
    public fun test_as_collateral_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 301);
            logic::as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID
            );
            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 302);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EIS_ISOLATED_ASSET)]
    public fun test_as_collateral_with_isolated_asset() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            ONE
        );

        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 301);
            logic::as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                ISOLATE_POOL_ID
            );
            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 302);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_supply() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_pool = btc_pool;
        let supply_pool_id = BTC_POOL_ID;
        let supply_user_id = 0;
        let supply_amount = ONE;
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
    public fun test_supply_isolate_asset() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let supply_pool = isolate_pool;
        let supply_pool_id = ISOLATE_POOL_ID;
        let supply_user_id = 0;
        let supply_amount = ONE;
        supply_scenario(
            scenario,
            creator,
            supply_pool,
            supply_pool_id,
            supply_user_id,
            supply_amount
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage = test_scenario::take_shared<Storage>(scenario);

            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 201);
            assert!(logic::is_isolation_mode(&mut storage, 0), 202);

            test_scenario::return_shared(storage);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_supply_other_asset_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage = test_scenario::take_shared<Storage>(scenario);

            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 201);
            assert!(logic::is_isolation_mode(&mut storage, 0), 202);

            test_scenario::return_shared(storage);
        };

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage = test_scenario::take_shared<Storage>(scenario);

            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 301);

            test_scenario::return_shared(storage);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_supply_isolate_asset_with_other_asset() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            ONE
        );

        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        test_scenario::next_tx(scenario, creator);
        {
            let storage = test_scenario::take_shared<Storage>(scenario);

            assert!(logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 201);

            test_scenario::return_shared(storage);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EIS_LOAN)]
    public fun test_supply_with_loan_asset() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        // User 0 supply usdt
        supply_scenario(scenario, creator, btc_pool, USDT_POOL_ID, 0, supply_usdt_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_withdraw() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_amount = ONE;
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let withdraw_amount = ONE / 2;

            // Withdraw
            logic::execute_withdraw(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID,
                withdraw_amount
            );
            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                btc_pool,
                LENDING_APP_ID,
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
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_withdraw_max_amount() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let supply_amount = ONE;
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_amount);
        supply_scenario(scenario, creator, isolate_pool, ISOLATE_POOL_ID, 0, supply_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let withdraw_amount = U256_MAX;

            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 201);

            // Withdraw max amount
            let actual_amount = logic::execute_withdraw(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID,
                withdraw_amount
            );
            assert!(actual_amount == supply_amount, 202);
            assert!(!logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 203);

            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                btc_pool,
                LENDING_APP_ID,
                actual_amount
            );

            assert!(logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 204);

            // Withdraw max amount
            let actual_amount = logic::execute_withdraw(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                ISOLATE_POOL_ID,
                withdraw_amount
            );
            assert!(actual_amount == supply_amount, 205);
            assert!(!logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 206);

            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                isolate_pool,
                LENDING_APP_ID,
                actual_amount
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ENOT_HEALTH)]
    public fun test_withdraw_with_not_health() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

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
            let clock = test_scenario::take_shared<Clock>(scenario);
            let withdraw_amount = supply_btc_amount;

            // Withdraw
            logic::execute_withdraw(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID,
                withdraw_amount
            );
            pool_manager::remove_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                btc_pool,
                LENDING_APP_ID,
                withdraw_amount
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_borrow() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ECOLLATERAL_AS_LOAN)]
    public fun test_borrow_with_collateral() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 0 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, supply_usdt_amount);

        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ELIQUID_AS_LOAN)]
    public fun test_borrow_with_liquid_asset() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_btc_amount = ONE;

        // User 0 supply 1 isolate
        supply_scenario(scenario, creator, isolate_pool, ISOLATE_POOL_ID, 0, supply_btc_amount);

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);

        // User 1 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 1, supply_btc_amount);

        // User 0 borrow 1 btc
        borrow_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_borrow_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_usdt_amount = 1000 * ONE;
        let borrow_usdt_amount = 10 * ONE;

        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EREACH_BORROW_CEILING)]
    public fun test_borrow_ceiling_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_usdt_amount = 5000 * ONE;

        // usdt borrow ceiling == 1000 * ONE
        let borrow1_usdt_amount = 500 * ONE;
        let borrow2_usdt_amount = 501 * ONE;

        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            1000 * ONE
        );

        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 500 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow1_usdt_amount);

        // User 0 borrow 501 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow2_usdt_amount);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EBORROW_UNISOLATED)]
    public fun test_borrow_invalid_asset_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");

        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            0,
            ONE
        );

        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 1, ONE);

        // User 0 borrow 100 satosi
        borrow_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, 100);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ENOT_BORROWABLE)]
    public fun test_borrow_isolated_asset() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let btc_pool = dola_address::create_dola_address(0, b"BTC");

        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, ONE);

        supply_scenario(
            scenario,
            creator,
            isolate_pool,
            ISOLATE_POOL_ID,
            1,
            100 * ONE
        );

        // User 0 borrow 1 isolate
        borrow_scenario(scenario, creator, isolate_pool, ISOLATE_POOL_ID, 0, ONE);

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_repay() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

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
            let clock = test_scenario::take_shared<Clock>(scenario);

            let repay_usdt_amount = 1000 * ONE;

            // User 0 repay 1000 usdt
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
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
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_repay_with_excess_amount() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 5000 * ONE;

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
            let clock = test_scenario::take_shared<Clock>(scenario);

            let repay_usdt_amount = 6000 * ONE;

            assert!(logic::is_loan(&mut storage, 0, USDT_POOL_ID), 201);

            // User 0 repay 6000 usdt
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDT_POOL_ID,
                repay_usdt_amount
            );

            // The excess balance of the user repaying the debt will become a liquid asset.
            assert!(logic::is_liquid_asset(&mut storage, 0, USDT_POOL_ID), 202);
            assert!(
                storage::get_user_scaled_otoken(
                    &mut storage,
                    0,
                    USDT_POOL_ID
                ) == (repay_usdt_amount - borrow_usdt_amount),
                203
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_repay_in_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_isolate_amount = ONE;
        let supply_usdt_amount = 1000 * ONE;
        let borrow_usdt_amount = 50 * ONE;

        // User 0 supply 1 isolate
        supply_scenario(scenario, creator, isolate_pool, ISOLATE_POOL_ID, 0, supply_isolate_amount);
        // User 1 supply 1000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 50 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_isolation_mode(&mut storage, 0), 201);
            assert!(storage::get_isolate_debt(&mut storage, ISOLATE_POOL_ID) == borrow_usdt_amount, 202);

            let repay_usdt_amount = 10 * ONE;

            // User 0 repay 10 usdt
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDT_POOL_ID,
                repay_usdt_amount
            );

            assert!(
                storage::get_isolate_debt(&mut storage, ISOLATE_POOL_ID) == (borrow_usdt_amount - repay_usdt_amount),
                203
            );

            let repay_usdt_amount = 100 * ONE;

            // User 0 repay 10 usdt
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDT_POOL_ID,
                repay_usdt_amount
            );

            assert!(storage::get_isolate_debt(&mut storage, ISOLATE_POOL_ID) == 0, 204);
            assert!(logic::is_liquid_asset(&mut storage, 0, USDT_POOL_ID), 205);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_repay_exit_isolation() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let isolate_pool = dola_address::create_dola_address(0, b"ISOLATE");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_isolate_amount = ONE;
        let supply_usdt_amount = 1000 * ONE;
        let borrow_usdt_amount = 50 * ONE;

        // User 0 supply 1 isolate
        supply_scenario(scenario, creator, isolate_pool, ISOLATE_POOL_ID, 0, supply_isolate_amount);
        // User 1 supply 1000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 50 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_cap = pool_manager::register_manager_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            assert!(logic::is_isolation_mode(&mut storage, 0), 201);

            let repay_usdt_amount = 50 * ONE;

            // User 0 repay 1000 usdt
            pool_manager::add_liquidity(
                &pool_manager_cap,
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDT_POOL_ID,
                repay_usdt_amount
            );

            // Check user dtoken
            assert!(
                logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID) == (borrow_usdt_amount - repay_usdt_amount),
                202
            );
            // Check user total loan
            assert!(logic::user_total_loan_value(&mut storage, &mut oracle, 0) == 0, 203);
            // After all debts are paid, you can cancel the collateral and exit isolated mode.
            assert!(logic::is_isolation_mode(&mut storage, 0), 204);

            logic::cancel_as_collateral(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                ISOLATE_POOL_ID
            );
            assert!(!logic::is_isolation_mode(&mut storage, 0), 205);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            pool_manager::destroy_manager(pool_manager_cap);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_execute_liquidate() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 50000 * ONE;

        let user_btc_value = 20000 * ONE;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = math::ray_div(math::ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 0 borrow max usdt - 1
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount - 1);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            // Check user HF > 1
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 104);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1999900);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            assert!(
                logic::user_health_factor(&mut storage, &mut oracle, 0) * 100 / RAY == TARGET_HEALTH_FACTOR * 100 / RAY,
                106
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_1() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let eth_pool = dola_address::create_dola_address(0, b"ETH");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let usdc_pool = dola_address::create_dola_address(0, b"USDC");
        let supply_btc_amount = ONE;
        let supply_eth_amount = ONE;
        let supply_usdt_amount = 50000 * ONE;
        let supply_usdc_amount = 50000 * ONE;

        let user_btc_value = 20000 * ONE;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = math::ray_div(math::ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * ONE;
        let borrow_usdc_value = math::ray_div(math::ray_mul(user_eth_value, ETH_CF), USDC_BF);
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
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount - ONE);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount - ONE);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID,
            );

            assert!(
                logic::user_health_factor(&mut storage, &mut oracle, 0) * 100 / RAY == TARGET_HEALTH_FACTOR * 100 / RAY,
                106
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_2() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let eth_pool = dola_address::create_dola_address(0, b"ETH");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let usdc_pool = dola_address::create_dola_address(0, b"USDC");
        let supply_btc_amount = ONE;
        let supply_eth_amount = ONE;
        let supply_usdt_amount = 50000 * ONE;
        let supply_usdc_amount = 50000 * ONE;

        let user_btc_value = 20000 * ONE;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = math::ray_div(math::ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * ONE;
        let borrow_usdc_value = math::ray_div(math::ray_mul(user_eth_value, ETH_CF), USDC_BF);
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
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount - ONE);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount - ONE);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdt debt to get eth
            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                ETH_POOL_ID,
                USDT_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_3() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let eth_pool = dola_address::create_dola_address(0, b"ETH");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let usdc_pool = dola_address::create_dola_address(0, b"USDC");
        let supply_btc_amount = ONE;
        let supply_eth_amount = ONE;
        let supply_usdt_amount = 50000 * ONE;
        let supply_usdc_amount = 50000 * ONE;

        let user_btc_value = 20000 * ONE;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = math::ray_div(math::ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * ONE;
        let borrow_usdc_value = math::ray_div(math::ray_mul(user_eth_value, ETH_CF), USDC_BF);
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
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount - ONE);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount - ONE);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdc debt to get btc
            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDC_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets_4() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let eth_pool = dola_address::create_dola_address(0, b"ETH");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let usdc_pool = dola_address::create_dola_address(0, b"USDC");
        let supply_btc_amount = ONE;
        let supply_eth_amount = ONE;
        let supply_usdt_amount = 50000 * ONE;
        let supply_usdc_amount = 50000 * ONE;

        let user_btc_value = 20000 * ONE;
        // btc_value * BTC_CF = usdt_value * USDT_BF
        let borrow_usdt_value = math::ray_div(math::ray_mul(user_btc_value, BTC_CF), USDT_BF);
        let borrow_usdt_amount = borrow_usdt_value;

        let user_eth_value = 1500 * ONE;
        let borrow_usdc_value = math::ray_div(math::ray_mul(user_eth_value, ETH_CF), USDC_BF);
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
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount - ONE);
        // User 0 borrow usdc with all eth
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount - ONE);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            // Simulate BTC price drop
            oracle::update_token_price(&oracle_cap, &mut oracle, BTC_POOL_ID, 1950000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 105);

            // User 1 liquidate user 0 usdc debt to get eth
            logic::execute_liquidate(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                ETH_POOL_ID,
                USDC_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_average_liquidity() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_btc_amount = ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let storage_cap = storage::register_storage_cap_for_testing();
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            let average_liquidity_0 = storage::get_user_average_liquidity(&mut storage, 0);
            // The initial average liquidity is 0
            assert!(average_liquidity_0 == 0, 201);

            clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);

            logic::update_average_liquidity(&storage_cap, &mut storage, &mut oracle, &clock, 0);
            let average_liquidity_1 = storage::get_user_average_liquidity(&mut storage, 0);
            let health_value_1 = logic::user_health_collateral_value(&mut storage, &mut oracle, 0);
            // [average_liquidity = health_value = collateral_value - loan_value]
            assert!(average_liquidity_1 == health_value_1, 202);

            clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY / 2);

            logic::execute_supply(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                0,
                ONE
            );

            let average_liquidity_2 = storage::get_user_average_liquidity(&mut storage, 0);
            let health_value_2 = logic::user_health_collateral_value(&mut storage, &mut oracle, 0);
            // Average liquidity accumulates if a user performs an operation in a day.
            assert!(average_liquidity_2 == average_liquidity_1 / 2 + health_value_2 / 2, 203);

            clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);

            logic::execute_supply(
                &storage_cap,
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                0,
                ONE
            );

            let average_liquidity = storage::get_user_average_liquidity(&mut storage, 0);
            let health_value = logic::user_health_collateral_value(&mut storage, &mut oracle, 0);
            // If the user operates in the protocol for more than one day, the accumulated average liquidity will return to zero.
            assert!(average_liquidity == health_value, 204);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_state_with_low_utilization() {
        // 30% utilization
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 3000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 3000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            let before_borrow_index = storage::get_borrow_index(&mut storage, USDT_POOL_ID);
            let before_liquidity_index = storage::get_liquidity_index(&mut storage, USDT_POOL_ID);
            assert!(before_borrow_index == RAY, 201);
            assert!(before_liquidity_index == RAY, 202);

            let day = 0;

            while (day < 365) {
                clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);
                logic::update_state(&storage_cap, &mut storage, &clock, USDT_POOL_ID);
                day = day + 1;
            };

            let after_borrow_index = storage::get_borrow_index(&mut storage, USDT_POOL_ID);
            let after_liquidity_index = storage::get_liquidity_index(&mut storage, USDT_POOL_ID);
            // Ensure that index will not grow too fast when the utilization rate is low.
            // borrow rate 4.1% , liquidity rate 1.1%
            assert!(after_borrow_index < 2 * RAY, 203);
            assert!(after_liquidity_index < 2 * RAY, 204);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_state_with_high_utilization() {
        // utilization 80%
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 8000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 7000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let storage_cap = storage::register_storage_cap_for_testing();
            let oracle_cap = test_scenario::take_from_sender<OracleCap>(scenario);
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);

            let before_borrow_index = storage::get_borrow_index(&mut storage, USDT_POOL_ID);
            let before_liquidity_index = storage::get_liquidity_index(&mut storage, USDT_POOL_ID);
            assert!(before_borrow_index == RAY, 201);
            assert!(before_liquidity_index == RAY, 202);

            let day = 0;

            while (day < 365) {
                clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);
                logic::update_state(&storage_cap, &mut storage, &clock, USDT_POOL_ID);
                day = day + 1;
            };

            let after_borrow_index = storage::get_borrow_index(&mut storage, USDT_POOL_ID);
            let after_liquidity_index = storage::get_liquidity_index(&mut storage, USDT_POOL_ID);
            // Ensure that index will not grow too fast when the utilization rate is high.
            // borrow rate 199.9% , liquidity rate 143.93%
            assert!(after_borrow_index < 10 * RAY, 203);
            assert!(after_liquidity_index < 10 * RAY, 204);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(scenario, oracle_cap);
        };

        test_scenario::end(scenario_val);
    }
}
