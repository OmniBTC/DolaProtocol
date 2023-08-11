// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

#[test_only]
module dola_protocol::logic_tests {
    use std::ascii;

    use sui::clock::{Self, Clock};
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::app_manager::{Self, TotalAppInfo};
    use dola_protocol::boost;
    use dola_protocol::boost::RewardPool;
    use dola_protocol::dola_address::{Self, DolaAddress};
    use dola_protocol::genesis;
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage::{Self as storage, Storage};
    use dola_protocol::lending_logic as logic;
    use dola_protocol::oracle::{Self, PriceOracle};
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::ray_math as math;

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
    const SUI_POOL_ID: u16 = 4;

    /// 0.9
    const SUI_CF: u256 = 900000000000000000000000000;

    /// 1.1
    const SUI_BF: u256 = 1100000000000000000000000000;

    /// 4
    const ISOLATE_POOL_ID: u16 = 5;

    /// 0.7
    const ISOLATE_CF: u256 = 700000000000000000000000000;

    const SUPPLY_REWARD: u64 = 20000;

    const BORROW_REWARD: u64 = 40000;

    const REWARD_START_TIME: u64 = 0;

    const REWARD_END_TIME: u64 = 10000;

    public fun init_for_testing(ctx: &mut TxContext) {
        oracle::init_for_testing(ctx);
        app_manager::init_for_testing(ctx);
        pool_manager::init_for_testing(ctx);
    }

    public fun init_oracle(oracle: &mut PriceOracle, clock: &Clock) {
        let cap = genesis::register_governance_cap_for_testing();

        // set fresh price for testing
        oracle::set_price_fresh_time(
            &cap,
            oracle,
            100000
        );

        // register btc oracle
        oracle::register_token_price(
            &cap,
            oracle,
            x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",
            BTC_POOL_ID,
            3000000,
            2,
            clock
        );

        // register usdt oracle
        oracle::register_token_price(
            &cap,
            oracle,
            x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",
            USDT_POOL_ID,
            100,
            2,
            clock
        );

        // register usdc oracle
        oracle::register_token_price(
            &cap,
            oracle,
            x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",
            USDC_POOL_ID,
            100,
            2,
            clock
        );

        // register eth oracle
        oracle::register_token_price(
            &cap,
            oracle,
            x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",
            ETH_POOL_ID,
            200000,
            2,
            clock
        );

        // register eth oracle
        oracle::register_token_price(
            &cap,
            oracle,
            x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",
            SUI_POOL_ID,
            100,
            2,
            clock
        );

        // register isolate oracle
        oracle::register_token_price(
            &cap,
            oracle,
            x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e",
            ISOLATE_POOL_ID,
            10000,
            2,
            clock
        );

        genesis::destroy(cap);
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

        // register eth pool
        let pool = dola_address::create_dola_address(0, b"SUI");
        let pool_name = ascii::string(b"SUI");
        pool_manager::register_pool_id(
            &governance_cap,
            pool_manager_info,
            pool_name,
            SUI_POOL_ID,
            ctx
        );
        pool_manager::register_pool(&governance_cap, pool_manager_info, pool, SUI_POOL_ID);
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
            10000 * ONE,
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
            0,
            ETH_CF,
            ETH_BF,
            BASE_BORROW_RATE,
            BORROW_RATE_SLOPE1,
            BORROW_RATE_SLOPE2,
            OPTIMAL_UTILIZATION,
            ctx
        );

        // register sui reserve
        storage::register_new_reserve(
            &cap,
            storage,
            clock,
            SUI_POOL_ID,
            false,
            false,
            666,
            TREASURY_FACTOR,
            0,
            0,
            SUI_CF,
            SUI_BF,
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
            0,
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
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            init_oracle(&mut oracle, &clock);

            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
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
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            init_reserves(&mut storage, &clock, test_scenario::ctx(scenario));

            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };

        (scenario_val)
    }

    public fun init_supply_reward_pool(scenario: &mut Scenario, creator: address) {
        test_scenario::next_tx(scenario, creator);
        {
            let cap = genesis::register_governance_cap_for_testing();
            let storage = test_scenario::take_shared<Storage>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let supply_reward = coin::mint_for_testing<SUI>(SUPPLY_REWARD, ctx);
            boost::create_reward_pool(
                &cap,
                &mut storage,
                (REWARD_START_TIME as u256),
                (REWARD_END_TIME as u256),
                supply_reward,
                SUI_POOL_ID,
                lending_codec::get_supply_type(),
                ctx
            );

            test_scenario::return_shared(storage);
            genesis::destroy(cap);
        };
    }

    public fun init_supply_reward_pool_with_time(
        scenario: &mut Scenario,
        creator: address,
        start_time: u64,
        end_time: u64
    ) {
        test_scenario::next_tx(scenario, creator);
        {
            let cap = genesis::register_governance_cap_for_testing();
            let storage = test_scenario::take_shared<Storage>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let supply_reward = coin::mint_for_testing<SUI>(SUPPLY_REWARD, ctx);
            boost::create_reward_pool(
                &cap,
                &mut storage,
                (start_time as u256),
                (end_time as u256),
                supply_reward,
                SUI_POOL_ID,
                lending_codec::get_supply_type(),
                ctx
            );

            test_scenario::return_shared(storage);
            genesis::destroy(cap);
        };
    }

    public fun init_borrow_reward_pool(scenario: &mut Scenario, creator: address) {
        test_scenario::next_tx(scenario, creator);
        {
            let cap = genesis::register_governance_cap_for_testing();
            let storage = test_scenario::take_shared<Storage>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let borrow_reward = coin::mint_for_testing<SUI>(40000, ctx);
            boost::create_reward_pool(
                &cap,
                &mut storage,
                0,
                10000,
                borrow_reward,
                SUI_POOL_ID,
                lending_codec::get_borrow_type(),
                ctx
            );

            test_scenario::return_shared(storage);
            genesis::destroy(cap);
        };
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            pool_manager::add_liquidity(
                &mut pool_manager_info,
                supply_pool,
                LENDING_APP_ID,
                supply_amount,
            );

            let before_user_balance = logic::user_collateral_balance(&mut storage, supply_user_id, supply_pool_id);

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id,
                supply_pool_id,
                supply_amount
            );

            // check user otoken
            let after_user_balance = logic::user_collateral_balance(&mut storage, supply_user_id, supply_pool_id);
            assert!(after_user_balance - before_user_balance == supply_amount, 101);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let before_user_debt = logic::user_loan_balance(&mut storage, borrow_user_id, borrow_pool_id);

            logic::execute_borrow(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                borrow_user_id,
                borrow_pool_id,
                borrow_amount
            );

            pool_manager::remove_liquidity(
                &mut pool_manager_info,
                borrow_pool,
                LENDING_APP_ID,
                borrow_amount
            );

            // Check user dtoken
            let after_user_debt = logic::user_loan_balance(&mut storage, borrow_user_id, borrow_pool_id);
            assert!(after_user_debt - before_user_debt == borrow_amount, 103);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 201);
            logic::cancel_as_collateral(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 201);
            logic::cancel_as_collateral(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 201);
            assert!(logic::is_isolation_mode(&mut storage, 0), 202);
            logic::cancel_as_collateral(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_collateral(&mut storage, 0, ISOLATE_POOL_ID), 201);
            logic::cancel_as_collateral(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            logic::cancel_as_collateral(
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
            clock::destroy_for_testing(clock);
        };

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 301);
            logic::as_collateral(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_liquid_asset(&mut storage, 0, BTC_POOL_ID), 301);
            logic::as_collateral(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 301);
            logic::as_collateral(
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
            clock::destroy_for_testing(clock);
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
    public fun test_supply_with_reward() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        init_supply_reward_pool(scenario, creator);

        let sui_pool = dola_address::create_dola_address(0, b"SUI");
        let supply_pool_id = SUI_POOL_ID;
        let supply_user_id_0 = 0;
        let supply_amount_0 = ONE;

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let clock = clock::create_for_testing(ctx);

            pool_manager::add_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                supply_amount_0,
            );

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                supply_pool_id,
                supply_amount_0
            );

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration / 4 * 1000);

            let reward = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward) == SUPPLY_REWARD / 4, 101);

            transfer::public_transfer(reward, creator);
            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::share_for_testing(clock);
        };

        let supply_user_id_1 = 1;
        let supply_amount_1 = ONE;

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let ctx = test_scenario::ctx(scenario);

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_1,
                supply_pool_id,
                supply_amount_1
            );

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration / 2 * 1000);

            let reward_0 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            let reward_1 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_1,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward_0) == SUPPLY_REWARD / 4 / 2, 102);
            assert!(coin::value(&reward_0) == coin::value(&reward_1), 103);

            transfer::public_transfer(reward_0, creator);
            transfer::public_transfer(reward_1, creator);

            logic::execute_withdraw(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                supply_pool_id,
                supply_amount_0 / 2
            );

            clock::set_for_testing(&mut clock, duration / 4 * 3 * 1000);

            let reward_0 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            let reward_1 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_1,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward_0) == SUPPLY_REWARD / 4 / 3 + 1, 104);
            assert!(coin::value(&reward_1) == SUPPLY_REWARD / 4 / 3 * 2 + 1, 105);

            transfer::public_transfer(reward_0, creator);
            transfer::public_transfer(reward_1, creator);

            clock::set_for_testing(&mut clock, duration * 1000);

            let reward_0 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            let reward_1 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_1,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward_0) == SUPPLY_REWARD / 4 / 3 + 1, 106);
            assert!(coin::value(&reward_1) == SUPPLY_REWARD / 4 / 3 * 2 + 1, 107);

            transfer::public_transfer(reward_0, creator);
            transfer::public_transfer(reward_1, creator);

            clock::set_for_testing(&mut clock, (duration + 1000) * 1000);

            let reward_0 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            let reward_1 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_1,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward_0) == 0, 108);
            assert!(coin::value(&reward_1) == 0, 109);

            transfer::public_transfer(reward_0, creator);
            transfer::public_transfer(reward_1, creator);
            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_supply_with_multi_reward_pool() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        init_supply_reward_pool(scenario, creator);
        init_supply_reward_pool(scenario, creator);

        let sui_pool = dola_address::create_dola_address(0, b"SUI");
        let supply_pool_id = SUI_POOL_ID;
        let supply_user_id_0 = 0;
        let supply_amount_0 = ONE;

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_pool_0 = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let reward_pool_1 = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let clock = clock::create_for_testing(ctx);

            pool_manager::add_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                supply_amount_0,
            );

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                supply_pool_id,
                supply_amount_0
            );

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration / 4 * 1000);

            let reward_0 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_pool_0,
                &clock,
                ctx
            );

            let reward_1 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_pool_1,
                &clock,
                ctx
            );

            assert!(coin::value(&reward_0) == SUPPLY_REWARD / 4, 101);
            assert!(coin::value(&reward_1) == SUPPLY_REWARD / 4, 102);

            transfer::public_transfer(reward_0, creator);
            transfer::public_transfer(reward_1, creator);

            test_scenario::return_shared(reward_pool_0);
            test_scenario::return_shared(reward_pool_1);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::share_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_claim_supply_reward_before_start() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let sui_pool = dola_address::create_dola_address(0, b"SUI");
        let supply_pool_id = SUI_POOL_ID;
        let supply_user_id_0 = 0;
        let supply_amount_0 = ONE;

        init_supply_reward_pool_with_time(scenario, creator, REWARD_END_TIME, REWARD_END_TIME * 2);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let cap = genesis::register_governance_cap_for_testing();
            let ctx = test_scenario::ctx(scenario);
            let clock = clock::create_for_testing(ctx);

            pool_manager::add_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                supply_amount_0,
            );

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                supply_pool_id,
                supply_amount_0
            );

            clock::set_for_testing(&mut clock, (REWARD_END_TIME / 2) * 1000);

            let reward = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward) == 0, 101);

            transfer::public_transfer(reward, creator);

            let left_reward = boost::remove_reward_pool<SUI>(
                &cap,
                &mut storage,
                &mut reward_balance,
                SUI_POOL_ID,
                ctx
            );

            assert!(coin::value(&left_reward) == SUPPLY_REWARD, 102);

            transfer::public_transfer(left_reward, creator);

            genesis::destroy(cap);

            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::share_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_remove_supply_reward() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let sui_pool = dola_address::create_dola_address(0, b"SUI");
        let supply_pool_id = SUI_POOL_ID;
        let supply_user_id_0 = 0;
        let supply_amount_0 = ONE;

        init_supply_reward_pool(scenario, creator);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let cap = genesis::register_governance_cap_for_testing();
            let ctx = test_scenario::ctx(scenario);
            let clock = clock::create_for_testing(ctx);

            pool_manager::add_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                supply_amount_0,
            );

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                supply_pool_id,
                supply_amount_0
            );

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration / 2 * 1000);

            let reward = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward) == SUPPLY_REWARD / 2, 101);

            transfer::public_transfer(reward, creator);

            let left_reward = boost::remove_reward_pool<SUI>(
                &cap,
                &mut storage,
                &mut reward_balance,
                SUI_POOL_ID,
                ctx
            );

            assert!(coin::value(&left_reward) == SUPPLY_REWARD / 2, 102);

            transfer::public_transfer(left_reward, creator);

            genesis::destroy(cap);

            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::share_for_testing(clock);
        };

        init_supply_reward_pool(scenario, creator);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let cap = genesis::register_governance_cap_for_testing();
            let ctx = test_scenario::ctx(scenario);
            let clock = clock::create_for_testing(ctx);

            pool_manager::add_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                supply_amount_0,
            );

            logic::execute_supply(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                supply_pool_id,
                supply_amount_0
            );

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration * 1000);

            let reward = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_supply_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward) == SUPPLY_REWARD, 201);

            transfer::public_transfer(reward, creator);

            let left_reward = boost::remove_reward_pool<SUI>(
                &cap,
                &mut storage,
                &mut reward_balance,
                SUI_POOL_ID,
                ctx
            );

            assert!(coin::value(&left_reward) == 0, 202);
            coin::destroy_zero(left_reward);

            genesis::destroy(cap);

            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::share_for_testing(clock);
        };

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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            let withdraw_amount = ONE / 2;

            // Withdraw
            logic::execute_withdraw(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID,
                withdraw_amount
            );
            pool_manager::remove_liquidity(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            let withdraw_amount = U256_MAX;

            assert!(logic::is_collateral(&mut storage, 0, BTC_POOL_ID), 201);

            // Withdraw max amount
            let actual_amount = logic::execute_withdraw(
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
                &mut pool_manager_info,
                btc_pool,
                LENDING_APP_ID,
                actual_amount
            );

            assert!(logic::is_liquid_asset(&mut storage, 0, ISOLATE_POOL_ID), 204);

            // Withdraw max amount
            let actual_amount = logic::execute_withdraw(
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
                &mut pool_manager_info,
                isolate_pool,
                LENDING_APP_ID,
                actual_amount
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            let withdraw_amount = supply_btc_amount;

            // Withdraw
            logic::execute_withdraw(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                BTC_POOL_ID,
                withdraw_amount
            );
            pool_manager::remove_liquidity(
                &mut pool_manager_info,
                btc_pool,
                LENDING_APP_ID,
                withdraw_amount
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
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
    public fun test_borrow_with_reward() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        init_borrow_reward_pool(scenario, creator);

        let sui_pool = dola_address::create_dola_address(0, b"SUI");
        let supply_sui_amount = 1000 * ONE;
        let supply_user_id_0 = 0;
        let supply_user_id_1 = 1;
        let borrow_sui_amount = 100 * ONE;

        // User 0 supply 10000 sui
        supply_scenario(scenario, creator, sui_pool, SUI_POOL_ID, supply_user_id_0, supply_sui_amount);

        // User 1 supply 10000 sui
        supply_scenario(scenario, creator, sui_pool, BTC_POOL_ID, 1, supply_sui_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            let ctx = test_scenario::ctx(scenario);

            let before_user_debt = logic::user_loan_balance(&mut storage, supply_user_id_0, SUI_POOL_ID);

            logic::execute_borrow(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_0,
                SUI_POOL_ID,
                borrow_sui_amount
            );

            pool_manager::remove_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                borrow_sui_amount
            );

            // Check user dtoken
            let after_user_debt = logic::user_loan_balance(&mut storage, supply_user_id_0, SUI_POOL_ID);
            assert!(after_user_debt - before_user_debt == borrow_sui_amount, 301);

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration / 4 * 1000);

            let reward = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_borrow_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward) == BORROW_REWARD / 4, 302);

            transfer::public_transfer(reward, creator);

            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::share_for_testing(clock);
        };

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let reward_balance = test_scenario::take_shared<RewardPool<SUI>>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            let ctx = test_scenario::ctx(scenario);

            let before_user_debt = logic::user_loan_balance(&mut storage, supply_user_id_1, SUI_POOL_ID);

            logic::execute_borrow(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                supply_user_id_1,
                SUI_POOL_ID,
                borrow_sui_amount
            );

            pool_manager::remove_liquidity(
                &mut pool_manager_info,
                sui_pool,
                LENDING_APP_ID,
                borrow_sui_amount
            );

            // Check user dtoken
            let after_user_debt = logic::user_loan_balance(&mut storage, supply_user_id_1, SUI_POOL_ID);
            assert!(after_user_debt - before_user_debt == borrow_sui_amount, 401);

            let duration = REWARD_END_TIME - REWARD_START_TIME;

            clock::set_for_testing(&mut clock, duration / 2 * 1000);

            let reward_0 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_0,
                lending_codec::get_borrow_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            let reward_1 = boost::claim<SUI>(
                &mut storage,
                SUI_POOL_ID,
                supply_user_id_1,
                lending_codec::get_borrow_type(),
                &mut reward_balance,
                &clock,
                ctx
            );

            assert!(coin::value(&reward_0) == BORROW_REWARD / 4 / 2, 402);
            assert!(coin::value(&reward_1) == coin::value(&reward_0), 403);

            transfer::public_transfer(reward_0, creator);
            transfer::public_transfer(reward_1, creator);

            test_scenario::return_shared(reward_balance);
            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_borrow_with_liquid_asset() {
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

        // User 0 set usdt as liquid asset
        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            logic::cancel_as_collateral(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDT_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };

        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);

        // User 0 borrow 5000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

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

        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::end(scenario_val);
    }


    #[test]
    #[expected_failure(abort_code = logic::EREACH_SUPPLY_CEILING)]
    public fun test_supply_reach_ceiling() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;
        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_btc_amount = 5000 * ONE;

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            supply_btc_amount
        );

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            supply_btc_amount
        );

        supply_scenario(
            scenario,
            creator,
            btc_pool,
            BTC_POOL_ID,
            0,
            supply_btc_amount
        );

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EREACH_BORROW_CEILING)]
    public fun test_borrow_reach_ceiling() {
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let repay_usdt_amount = 1000 * ONE;

            // User 0 repay 1000 usdt
            pool_manager::add_liquidity(
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
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
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_repay_with_circular_borrow() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_usdt_amount = 10000 * ONE;
        let borrow_usdt_amount = 1000 * ONE;

        // User 1 supply 10000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, supply_usdt_amount);

        // User 0 borrow 1000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let repay_usdt_amount = 2000 * ONE;

            // User 0 repay 1000 usdt
            pool_manager::add_liquidity(
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDT_POOL_ID,
                repay_usdt_amount
            );

            // check user collaterals
            assert!(
                storage::get_user_collaterals(&mut storage, 0) == vector[USDT_POOL_ID],
                201
            );

            // check user liquid assets
            assert!(
                storage::get_user_liquid_assets(&mut storage, 0) == vector[],
                202
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let repay_usdt_amount = 6000 * ONE;

            assert!(logic::is_loan(&mut storage, 0, USDT_POOL_ID), 201);

            // User 0 repay 6000 usdt
            pool_manager::add_liquidity(
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_isolation_mode(&mut storage, 0), 201);
            assert!(storage::get_isolate_debt(&mut storage, ISOLATE_POOL_ID) == borrow_usdt_amount, 202);

            let repay_usdt_amount = 10 * ONE;

            // User 0 repay 10 usdt
            pool_manager::add_liquidity(
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
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
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
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
            clock::destroy_for_testing(clock);
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_isolation_mode(&mut storage, 0), 201);

            let repay_usdt_amount = 50 * ONE;

            // User 0 repay 1000 usdt
            pool_manager::add_liquidity(
                &mut pool_manager_info,
                usdt_pool,
                LENDING_APP_ID,
                repay_usdt_amount,
            );
            logic::execute_repay(
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
            clock::destroy_for_testing(clock);
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
        let borrow_usdt_amount = 20000 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 0 borrow 20000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            // Check detailed state

            // Check treasury state
            let treasury = storage::get_reserve_treasury(&mut storage, BTC_POOL_ID);
            let before_treasury_reserved = logic::user_collateral_balance(&mut storage, treasury, BTC_POOL_ID);

            // Check user 0 state
            assert!(logic::user_collateral_balance(&mut storage, 0, BTC_POOL_ID) == supply_btc_amount, 201);
            assert!(logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID) == borrow_usdt_amount, 202);
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 203);
            let before_user0_btc_balance = logic::user_collateral_balance(&mut storage, 0, BTC_POOL_ID);
            let before_user0_usdt_debt = logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID);

            // Check user 1 state
            assert!(logic::user_collateral_balance(&mut storage, 1, USDT_POOL_ID) == supply_usdt_amount, 204);
            assert!(logic::user_collateral_balance(&mut storage, 1, BTC_POOL_ID) == 0, 205);
            let before_user1_usdt_balance = logic::user_collateral_balance(&mut storage, 1, USDT_POOL_ID);

            // Simulate BTC price drop to 20000
            oracle::update_token_price(&mut oracle, BTC_POOL_ID, 2500000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 206);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            // Check treasury state
            let after_treasury_reserved = logic::user_collateral_balance(&mut storage, treasury, BTC_POOL_ID);
            let liquidation_reserved = after_treasury_reserved - before_treasury_reserved;

            // Check user 0 state
            let user0_btc_balance = logic::user_collateral_balance(&mut storage, 0, BTC_POOL_ID);
            let after_user0_usdt_debt = logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID);

            // Check user 1 state
            let user1_btc_balance = logic::user_collateral_balance(&mut storage, 1, BTC_POOL_ID);
            let after_user1_usdt_balance = logic::user_collateral_balance(&mut storage, 1, USDT_POOL_ID);

            // Check user 0 btc_balance + user 1 btc_balance + liquidation_reserved = supply_btc_amount
            assert!(user0_btc_balance + user1_btc_balance + liquidation_reserved == before_user0_btc_balance, 207);
            // Check that the USDT debt reduced by user 0 equals the USDT balance decreased by user 1
            assert!(
                before_user0_usdt_debt - after_user0_usdt_debt == before_user1_usdt_balance - after_user1_usdt_balance,
                208
            );
            // Check user 0 heath factor == 1.25
            assert!(
                get_percentage(logic::user_health_factor(&mut storage, &mut oracle, 0)) == get_percentage(
                    RAY + RAY / 4
                ),
                209
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::EIS_HEALTH)]
    public fun test_liquidate_with_health() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let usdt_pool = dola_address::create_dola_address(0, b"USDT");
        let supply_btc_amount = ONE;
        let supply_usdt_amount = 50000 * ONE;

        let borrow_usdt_amount = 1000;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 0 borrow max usdt - 1
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            // Check user HF > 1
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 201);

            // Simulate BTC price drop
            oracle::update_token_price(&mut oracle, BTC_POOL_ID, 1999900);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 202);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = logic::ENOT_COLLATERAL)]
    public fun test_liquidate_with_violator_liquid_asset() {
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
        // User 0 supply 1000 usdc as liquid asset
        supply_scenario(scenario, creator, usdt_pool, USDC_POOL_ID, 0, 1000 * ONE);
        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            assert!(logic::is_collateral(&mut storage, 0, USDC_POOL_ID), 201);
            logic::cancel_as_collateral(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                0,
                USDC_POOL_ID
            );
            assert!(logic::is_liquid_asset(&mut storage, 0, USDC_POOL_ID), 202);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };

        // User 0 borrow max usdt - 1
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount - 1);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            // Check user HF > 1
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 203);

            // Simulate BTC price drop
            oracle::update_token_price(&mut oracle, BTC_POOL_ID, 1999900);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 204);

            // User 1 liquidate user 0 usdt debt to get usdc
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                USDC_POOL_ID,
                USDT_POOL_ID
            );

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_deficit() {
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            // Check user 0 HF > 1
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 201);

            // Simulate BTC price has fallen sharply
            oracle::update_token_price(&mut oracle, BTC_POOL_ID, 1000000);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 202);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            // The violator's collateral is fined, but there is still debt, and eventually
            // the treasury takes over the debt, resulting in a systematic deficit.
            assert!(storage::get_user_scaled_otoken(&mut storage, 0, BTC_POOL_ID) == 0, 203);
            assert!(storage::get_user_scaled_dtoken(&mut storage, 0, USDT_POOL_ID) == 0, 204);

            let treasury = storage::get_reserve_treasury(&mut storage, USDT_POOL_ID);
            assert!(storage::get_user_scaled_dtoken(&mut storage, treasury, USDT_POOL_ID) >= 0, 205);

            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_cover_liquidator_debt() {
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
        // User 1 borrow 0.1 btc
        borrow_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 1, ONE / 10);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            // Check user HF > 1
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) > RAY, 201);

            // Simulate BTC price drop
            oracle::update_token_price(&mut oracle, BTC_POOL_ID, 1999900);

            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 202);
            // User 1 exist btc debt
            assert!(logic::is_loan(&mut storage, 1, BTC_POOL_ID), 203);
            assert!(storage::get_user_scaled_dtoken(&mut storage, 1, BTC_POOL_ID) > 0, 204);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
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
                205
            );
            // User 1's btc debt is cleared
            assert!(logic::is_liquid_asset(&mut storage, 1, BTC_POOL_ID), 206);
            assert!(storage::get_user_scaled_dtoken(&mut storage, 1, BTC_POOL_ID) == 0, 207);


            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_liquidate_with_multi_assets() {
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

        let borrow_usdt_amount = 20000 * ONE;
        let borrow_usdc_amount = 1500 * ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);
        // User 0 supply 1 eth
        supply_scenario(scenario, creator, eth_pool, ETH_POOL_ID, 0, supply_eth_amount);

        // User 1 supply 50000 usdt
        supply_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 1, supply_usdt_amount);
        // User 1 supply 50000 usdc
        supply_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 1, supply_usdc_amount);

        // User 0 borrow 20000 usdt
        borrow_scenario(scenario, creator, usdt_pool, USDT_POOL_ID, 0, borrow_usdt_amount);
        // User 0 borrow 1500 usdc
        borrow_scenario(scenario, creator, usdc_pool, USDC_POOL_ID, 0, borrow_usdc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            // Simulate BTC price drop
            oracle::update_token_price(&mut oracle, BTC_POOL_ID, 2500000);

            // Check user 0 state
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 201);
            let before_usdc_debt = logic::user_loan_balance(&mut storage, 0, USDC_POOL_ID);
            let before_usdt_debt = logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID);

            // Check user 1 state
            let before_usdc_balance = logic::user_collateral_balance(&mut storage, 1, USDC_POOL_ID);
            let before_usdt_balance = logic::user_collateral_balance(&mut storage, 1, USDT_POOL_ID);

            // User 1 liquidate user 0 usdt debt to get eth
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                ETH_POOL_ID,
                USDT_POOL_ID
            );

            // collateral value 2000 ,  debt value 20000
            // Too little collateral was liquidated, the collateral was liquidated, but the debt was still exist.
            let after_usdt_debt = logic::user_loan_balance(&mut storage, 0, USDT_POOL_ID);
            let after_usdt_balance = logic::user_collateral_balance(&mut storage, 1, USDT_POOL_ID);
            assert!(before_usdt_debt - after_usdt_debt == before_usdt_balance - after_usdt_balance, 202);

            // Check user0 state
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 203);
            assert!(after_usdt_debt > 0, 204);
            let user_0_eth_balance = logic::user_collateral_balance(&mut storage, 0, ETH_POOL_ID);
            assert!(user_0_eth_balance == 0, 205);

            // User 1 liquidate user 0 usdc debt to get btc
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDC_POOL_ID
            );

            // collateral value 25000 ,  debt value 1500
            // Too little debt has been liquidated, so much of the collateral remains
            // unliquidated and the recovery of health factors is less.
            let after_usdc_debt = logic::user_loan_balance(&mut storage, 0, USDC_POOL_ID);
            let after_usdc_balance = logic::user_collateral_balance(&mut storage, 1, USDC_POOL_ID);
            assert!(before_usdc_debt - after_usdc_debt == before_usdc_balance - after_usdc_balance, 206);

            // Check user0 state
            assert!(logic::user_health_factor(&mut storage, &mut oracle, 0) < RAY, 207);
            assert!(after_usdc_debt == 0, 208);

            // User 1 liquidate user 0 usdt debt to get btc
            logic::execute_liquidate(
                &mut pool_manager_info,
                &mut storage,
                &mut oracle,
                &clock,
                1,
                0,
                BTC_POOL_ID,
                USDT_POOL_ID
            );

            // Check user0 health factor == 1.25
            assert!(
                get_percentage(logic::user_health_factor(&mut storage, &mut oracle, 0)) == get_percentage(
                    RAY + RAY / 4
                ),
                209
            );


            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_average_liquidity_for_testing() {
        let creator = @0xA;

        let scenario_val = init_test_scenario(creator);
        let scenario = &mut scenario_val;

        let btc_pool = dola_address::create_dola_address(0, b"BTC");
        let supply_btc_amount = ONE;

        // User 0 supply 1 btc
        supply_scenario(scenario, creator, btc_pool, BTC_POOL_ID, 0, supply_btc_amount);

        test_scenario::next_tx(scenario, creator);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let average_liquidity_0 = storage::get_user_average_liquidity(&mut storage, 0);
            // The initial average liquidity is 0
            assert!(average_liquidity_0 == 0, 201);

            clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);

            logic::update_average_liquidity_for_testing(&mut storage, &mut oracle, &clock, 0);
            let average_liquidity_1 = storage::get_user_average_liquidity(&mut storage, 0);
            let health_value_1 = logic::user_health_collateral_value(&mut storage, &mut oracle, 0);
            // [average_liquidity = health_value = collateral_value - loan_value]
            assert!(average_liquidity_1 == health_value_1, 202);

            clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY / 2);

            logic::execute_supply(
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
            clock::destroy_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_state_for_testing_with_low_utilization() {
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let before_borrow_index = storage::get_borrow_index(&mut storage, USDT_POOL_ID);
            let before_liquidity_index = storage::get_liquidity_index(&mut storage, USDT_POOL_ID);
            assert!(before_borrow_index == RAY, 201);
            assert!(before_liquidity_index == RAY, 202);

            let day = 0;

            while (day < 365) {
                clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);
                logic::update_state_for_testing(&mut storage, &clock, USDT_POOL_ID);
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
            clock::destroy_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_state_for_testing_with_high_utilization() {
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let before_borrow_index = storage::get_borrow_index(&mut storage, USDT_POOL_ID);
            let before_liquidity_index = storage::get_liquidity_index(&mut storage, USDT_POOL_ID);
            assert!(before_borrow_index == RAY, 201);
            assert!(before_liquidity_index == RAY, 202);

            let day = 0;

            while (day < 365) {
                clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);
                logic::update_state_for_testing(&mut storage, &clock, USDT_POOL_ID);
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
            clock::destroy_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_system_normal_profit_with_low_utilization() {
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let total_supply = supply_usdt_amount;
            let total_borrow = borrow_usdt_amount;

            let day = 0;

            while (day < 365) {
                clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);
                logic::update_state_for_testing(&mut storage, &clock, USDT_POOL_ID);
                day = day + 1;

                let current_supply = logic::total_otoken_supply(&mut storage, USDT_POOL_ID);
                let current_debt = logic::total_dtoken_supply(&mut storage, USDT_POOL_ID);

                let user_profit = current_supply - total_supply;
                let system_profit = current_debt - total_borrow;
                assert!(system_profit >= user_profit, 201);
            };


            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_system_normal_profit_with_high_utilization() {
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
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let storage = test_scenario::take_shared<Storage>(scenario);
            let oracle = test_scenario::take_shared<PriceOracle>(scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));

            let total_supply = supply_usdt_amount;
            let total_borrow = borrow_usdt_amount;


            let day = 0;

            while (day < 365) {
                clock::increment_for_testing(&mut clock, MILLISECONDS_PER_DAY);
                logic::update_state_for_testing(&mut storage, &clock, USDT_POOL_ID);
                day = day + 1;

                let current_supply = logic::total_otoken_supply(&mut storage, USDT_POOL_ID);
                let current_debt = logic::total_dtoken_supply(&mut storage, USDT_POOL_ID);

                let user_profit = current_supply - total_supply;
                let system_profit = current_debt - total_borrow;
                assert!(system_profit >= user_profit, 201);
            };


            test_scenario::return_shared(pool_manager_info);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(oracle);
            clock::destroy_for_testing(clock);
        };

        test_scenario::end(scenario_val);
    }
}
