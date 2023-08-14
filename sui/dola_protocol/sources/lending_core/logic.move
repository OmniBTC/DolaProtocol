// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::lending_logic {
    use std::vector;

    use sui::clock::Clock;
    use sui::event;

    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage::{Self as storage, is_isolated_asset, Storage};
    use dola_protocol::oracle::{Self, check_fresh_price, PriceOracle};
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::rates;
    use dola_protocol::ray_math as math;
    use dola_protocol::scaled_balance;
    use dola_protocol::boost;
    use sui::event::emit;

    friend dola_protocol::lending_core_wormhole_adapter;
    friend dola_protocol::lending_portal;

    #[test_only]
    friend dola_protocol::logic_tests;

    const U256_MAX: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// 20%
    const MAX_DISCOUNT: u256 = 200000000000000000000000000;

    /// HF 1.25
    const TARGET_HEALTH_FACTOR: u256 = 1250000000000000000000000000;

    /// Errors
    const ECOLLATERAL_AS_LOAN: u64 = 0;

    const ELIQUID_AS_LOAN: u64 = 1;

    const ENOT_HEALTH: u64 = 2;

    const EIS_HEALTH: u64 = 3;

    const ENOT_COLLATERAL: u64 = 4;

    const ENOT_LOAN: u64 = 5;

    const EINVALID_POOL_ID: u64 = 6;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 7;

    const EREACH_BORROW_CEILING: u64 = 8;

    const EBORROW_UNISOLATED: u64 = 9;

    const ENOT_BORROWABLE: u64 = 10;

    const ENOT_LIQUID_ASSET: u64 = 11;

    const EIN_ISOLATION: u64 = 12;

    const ENOT_USER: u64 = 13;

    const EIS_ISOLATED_ASSET: u64 = 14;

    const EIS_LOAN: u64 = 15;

    const EREACH_SUPPLY_CEILING: u64 = 16;

    const ENOT_REWARD_POOL: u64 = 17;

    /// Lending core execute event
    struct LendingCoreExecuteEvent has drop, copy {
        user_id: u64,
        amount: u256,
        pool_id: u16,
        violator_id: u64,
        call_type: u8
    }

    struct LendingReserveStatsEvent has drop, copy {
        pool_id: u16,
        otoken_scaled_amount: u256,
        dtoken_scaled_amount: u256,
        supply_rate: u256,
        borrow_rate: u256,
        supply_index: u256,
        borrow_index: u256,
    }

    struct LendingUserStatsEvent has drop, copy {
        pool_id: u16,
        user_id: u64,
        otoken_scaled_amount: u256,
        dtoken_scaled_amount: u256,
        hf: u256
    }


    /// === Friend Functions ===

    fun emit_user_stats(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        dola_user_id: u64,
    ) {
        emit(LendingUserStatsEvent {
            pool_id: dola_pool_id,
            user_id: dola_user_id,
            otoken_scaled_amount: storage::get_user_scaled_otoken(storage, dola_user_id, dola_pool_id),
            dtoken_scaled_amount: storage::get_user_scaled_dtoken(storage, dola_user_id, dola_pool_id),
            hf: user_health_factor(storage, oracle, dola_user_id)
        });
    }

    fun emit_reserve_stats(
        storage: &mut Storage,
        dola_pool_id: u16
    ) {
        emit(LendingReserveStatsEvent {
            pool_id: dola_pool_id,
            otoken_scaled_amount: storage::get_otoken_scaled_total_supply(storage, dola_pool_id),
            dtoken_scaled_amount: storage::get_dtoken_scaled_total_supply(storage, dola_pool_id),
            supply_rate: storage::get_liquidity_rate(storage, dola_pool_id),
            borrow_rate: storage::get_borrow_rate(storage, dola_pool_id),
            supply_index: storage::get_borrow_index(storage, dola_pool_id),
            borrow_index: storage::get_borrow_index(storage, dola_pool_id),
        });
    }

    public(friend) fun execute_liquidate(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        liquidator: u64,
        violator: u64,
        collateral: u16,
        loan: u16
    ) {
        assert!(is_collateral(storage, violator, collateral), ENOT_COLLATERAL);
        assert!(is_loan(storage, violator, loan), ENOT_LOAN);
        assert!(is_collateral(storage, liquidator, loan), ENOT_COLLATERAL);

        update_state(storage, clock, loan);
        update_state(storage, clock, collateral);
        // The most recent user contribution is required to calculate the liquidation discount.
        update_average_liquidity(storage, oracle, clock, liquidator);

        // Check the freshness of the price when performing the liquidation logic.
        check_user_fresh_price(oracle, storage, violator, clock);

        assert!(!is_health(storage, oracle, violator), EIS_HEALTH);

        let (max_liquidable_collateral, max_liquidable_debt) = calculate_max_liquidation(
            storage,
            oracle,
            liquidator,
            violator,
            collateral,
            loan
        );

        let treasury_factor = storage::get_treasury_factor(storage, collateral);
        // Use the user's existing collateral to liquidate the debt.
        let repay_debt = user_collateral_balance(storage, liquidator, loan);

        let (actual_liquidable_collateral, actual_liquidable_debt, liquidator_acquired_collateral, treasury_reserved_collateral) = calculate_actual_liquidation(
            oracle,
            collateral,
            max_liquidable_collateral,
            loan,
            max_liquidable_debt,
            repay_debt,
            treasury_factor
        );

        let treasury = storage::get_reserve_treasury(storage, collateral);
        // For violator
        burn_dtoken(storage, violator, loan, actual_liquidable_debt);
        burn_otoken(storage, violator, collateral, actual_liquidable_collateral);
        // For liquidator
        burn_otoken(storage, liquidator, loan, actual_liquidable_debt);
        // For treasury
        mint_otoken(storage, treasury, collateral, treasury_reserved_collateral);

        // Check if violator cause a lending deficit, use treasury to cover the deficit.
        if (has_deficit(storage, oracle, violator)) {
            cover_deficit(storage, violator);
        };

        // Give the collateral to the liquidator.
        if (is_loan(storage, liquidator, collateral)) {
            // If the liquidator has debt for the collateral, help the liquidator repay the debt first.
            let liquidator_debt = user_loan_balance(storage, liquidator, collateral);
            let liquidator_burned_debt = math::min(liquidator_debt, liquidator_acquired_collateral);
            burn_dtoken(storage, liquidator, collateral, liquidator_burned_debt);
            if (liquidator_acquired_collateral > liquidator_debt) {
                // If the liquidator has paid off the debt and still has the collateral left over,
                // the collateral is given to the user as a liquid asset.
                storage::remove_user_loan(storage, liquidator, collateral);
                mint_otoken(storage, liquidator, collateral, liquidator_acquired_collateral - liquidator_debt);
                storage::add_user_liquid_asset(storage, liquidator, collateral);
            }
        } else {
            mint_otoken(storage, liquidator, collateral, liquidator_acquired_collateral);
            // If the user does not have such asset, the collateral is sent to the user as a liquid asset.
            if (!is_collateral(storage, liquidator, collateral) && !is_liquid_asset(storage, liquidator, collateral)) {
                storage::add_user_liquid_asset(storage, liquidator, collateral);
            };
        };

        // Check liquidator health factor
        assert!(is_health(storage, oracle, liquidator), ENOT_HEALTH);

        update_interest_rate(pool_manager_info, storage, collateral, 0);
        update_interest_rate(pool_manager_info, storage, loan, 0);
        update_average_liquidity(storage, oracle, clock, violator);

        event::emit(LendingCoreExecuteEvent {
            user_id: liquidator,
            amount: actual_liquidable_collateral,
            pool_id: collateral,
            violator_id: violator,
            call_type: lending_codec::get_liquidate_type()
        });

        emit_reserve_stats(storage, collateral);
        emit_user_stats(storage, oracle, collateral, liquidator);
        emit_user_stats(storage, oracle, collateral, violator);

        emit_reserve_stats(storage, loan);
        emit_user_stats(storage, oracle, loan, liquidator);
        emit_user_stats(storage, oracle, loan, violator);
    }

    public(friend) fun execute_supply(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64,
        dola_pool_id: u16,
        supply_amount: u256,
    ) {
        // Check user info exist
        storage::ensure_user_info_exist(storage, clock, dola_user_id);
        assert!(storage::exist_reserve(storage, dola_pool_id), EINVALID_POOL_ID);
        assert!(not_reach_supply_ceiling(storage, dola_pool_id, supply_amount), EREACH_SUPPLY_CEILING);
        boost::boost_pool(storage, dola_pool_id, dola_user_id, lending_codec::get_supply_type(), clock);

        update_state(storage, clock, dola_pool_id);
        mint_otoken(storage, dola_user_id, dola_pool_id, supply_amount);

        // Add asset type for the new asset
        if (!is_collateral(storage, dola_user_id, dola_pool_id) && !is_liquid_asset(
            storage,
            dola_user_id,
            dola_pool_id
        )) {
            if (is_isolation_mode(storage, dola_user_id)) {
                // Users cannot pledge other tokens as collateral in isolated mode.
                storage::add_user_liquid_asset(storage, dola_user_id, dola_pool_id);
            } else {
                if (!has_collateral(storage, dola_user_id)) {
                    // Isolated assets as collateral and the user enters isolation mode.
                    storage::add_user_collateral(storage, dola_user_id, dola_pool_id);
                } else {
                    if (storage::is_isolated_asset(storage, dola_pool_id)) {
                        // Isolated asset cannot be used as collateral when other collaterals are present.
                        storage::add_user_liquid_asset(storage, dola_user_id, dola_pool_id);
                    } else {
                        storage::add_user_collateral(storage, dola_user_id, dola_pool_id);
                    }
                }
            }
        };
        update_interest_rate(pool_manager_info, storage, dola_pool_id, 0);
        update_average_liquidity(storage, oracle, clock, dola_user_id);

        event::emit(LendingCoreExecuteEvent {
            user_id: dola_user_id,
            amount: supply_amount,
            pool_id: dola_pool_id,
            violator_id: 0,
            call_type: lending_codec::get_supply_type()
        });

        emit_reserve_stats(storage, dola_pool_id);
        emit_user_stats(storage, oracle, dola_pool_id, dola_user_id);
    }

    public(friend) fun execute_withdraw(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64,
        dola_pool_id: u16,
        withdraw_amount: u256,
    ): u256 {
        // Check user info exist
        storage::ensure_user_info_exist(storage, clock, dola_user_id);
        assert!(storage::exist_reserve(storage, dola_pool_id), EINVALID_POOL_ID);
        boost::boost_pool(storage, dola_pool_id, dola_user_id, lending_codec::get_withdraw_type(), clock);

        update_state(storage, clock, dola_pool_id);
        let otoken_amount = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        let actual_amount = math::min(withdraw_amount, otoken_amount);

        burn_otoken(storage, dola_user_id, dola_pool_id, actual_amount);

        // Check the freshness of the price
        check_user_fresh_price(oracle, storage, dola_user_id, clock);

        assert!(is_health(storage, oracle, dola_user_id), ENOT_HEALTH);
        if (actual_amount == otoken_amount) {
            // If the asset is all withdrawn, the asset type of the user is removed.
            if (is_collateral(storage, dola_user_id, dola_pool_id)) {
                storage::remove_user_collateral(storage, dola_user_id, dola_pool_id);
            } else {
                storage::remove_user_liquid_asset(storage, dola_user_id, dola_pool_id);
            }
        };
        update_interest_rate(pool_manager_info, storage, dola_pool_id, actual_amount);
        update_average_liquidity(storage, oracle, clock, dola_user_id);

        event::emit(LendingCoreExecuteEvent {
            user_id: dola_user_id,
            amount: actual_amount,
            pool_id: dola_pool_id,
            violator_id: 0,
            call_type: lending_codec::get_withdraw_type()
        });

        emit_reserve_stats(storage, dola_pool_id);
        emit_user_stats(storage, oracle, dola_pool_id, dola_user_id);

        actual_amount
    }

    public(friend) fun execute_borrow(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64,
        borrow_pool_id: u16,
        borrow_amount: u256,
    ) {
        // Check user info exist
        storage::ensure_user_info_exist(storage, clock, dola_user_id);
        assert!(storage::exist_reserve(storage, borrow_pool_id), EINVALID_POOL_ID);
        boost::boost_pool(storage, borrow_pool_id, dola_user_id, lending_codec::get_borrow_type(), clock);

        update_state(storage, clock, borrow_pool_id);

        assert!(!is_isolated_asset(storage, borrow_pool_id), ENOT_BORROWABLE);

        // In isolation mode, can only borrow the allowed assets
        if (is_isolation_mode(storage, dola_user_id)) {
            assert!(storage::can_borrow_in_isolation(storage, borrow_pool_id), EBORROW_UNISOLATED);
            assert!(not_reach_borrow_ceiling(storage, dola_user_id, borrow_amount), EREACH_BORROW_CEILING);
            add_isolate_debt(storage, dola_user_id, borrow_amount);
        };

        if (!is_loan(storage, dola_user_id, borrow_pool_id)) {
            storage::add_user_loan(storage, dola_user_id, borrow_pool_id);
        };

        mint_dtoken(storage, dola_user_id, borrow_pool_id, borrow_amount);

        // Check the freshness of the price
        check_user_fresh_price(oracle, storage, dola_user_id, clock);
        check_fresh_price(oracle, vector[borrow_pool_id], clock);

        assert!(is_health(storage, oracle, dola_user_id), ENOT_HEALTH);
        update_interest_rate(pool_manager_info, storage, borrow_pool_id, borrow_amount);
        update_average_liquidity(storage, oracle, clock, dola_user_id);

        event::emit(LendingCoreExecuteEvent {
            user_id: dola_user_id,
            amount: borrow_amount,
            pool_id: borrow_pool_id,
            violator_id: 0,
            call_type: lending_codec::get_borrow_type()
        });

        emit_reserve_stats(storage, borrow_pool_id);
        emit_user_stats(storage, oracle, borrow_pool_id, dola_user_id);
    }

    public(friend) fun execute_repay(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64,
        dola_pool_id: u16,
        repay_amount: u256,
    ) {
        storage::ensure_user_info_exist(storage, clock, dola_user_id);
        assert!(storage::exist_reserve(storage, dola_pool_id), EINVALID_POOL_ID);
        boost::boost_pool(storage, dola_pool_id, dola_user_id, lending_codec::get_repay_type(), clock);

        update_state(storage, clock, dola_pool_id);
        let debt = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let repay_debt = math::min(repay_amount, debt);
        burn_dtoken(storage, dola_user_id, dola_pool_id, repay_debt);

        if (is_isolation_mode(storage, dola_user_id)) {
            reduce_isolate_debt(storage, dola_user_id, repay_debt);
        };

        // Debt is paid off, moving asset out of the user's debt assets
        if (repay_amount >= debt) {
            storage::remove_user_loan(storage, dola_user_id, dola_pool_id);

            let excess_repay_amount = repay_amount - debt;
            // If the user overpays the debt, the excess goes directly to the user's liquid assets.
            if (excess_repay_amount > 0) {
                mint_otoken(storage, dola_user_id, dola_pool_id, excess_repay_amount);
                storage::add_user_liquid_asset(storage, dola_user_id, dola_pool_id);
            };
        };
        update_interest_rate(pool_manager_info, storage, dola_pool_id, 0);
        update_average_liquidity(storage, oracle, clock, dola_user_id);

        event::emit(LendingCoreExecuteEvent {
            user_id: dola_user_id,
            amount: repay_debt,
            pool_id: dola_pool_id,
            violator_id: 0,
            call_type: lending_codec::get_repay_type()
        });

        emit_reserve_stats(storage, dola_pool_id);
        emit_user_stats(storage, oracle, dola_pool_id, dola_user_id);
    }

    /// Turn liquid asset into collateral
    public(friend) fun as_collateral(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64,
        dola_pool_id: u16,
    ) {
        update_state(storage, clock, dola_pool_id);
        assert!(is_liquid_asset(storage, dola_user_id, dola_pool_id), ENOT_LIQUID_ASSET);
        // No other assets can be added as collateral in isolation mode.
        assert!(!is_isolation_mode(storage, dola_user_id), EIN_ISOLATION);

        if (has_collateral(storage, dola_user_id)) {
            // When there is collateral, isolated assets are not allowed to become collateral.
            assert!(!is_isolated_asset(storage, dola_pool_id), EIS_ISOLATED_ASSET);
        };

        storage::remove_user_liquid_asset(storage, dola_user_id, dola_pool_id);
        storage::add_user_collateral(storage, dola_user_id, dola_pool_id);

        update_interest_rate(pool_manager_info, storage, dola_pool_id, 0);
        update_average_liquidity(storage, oracle, clock, dola_user_id);

        event::emit(LendingCoreExecuteEvent {
            user_id: dola_user_id,
            amount: 0,
            pool_id: dola_pool_id,
            violator_id: 0,
            call_type: lending_codec::get_as_colleteral_type()
        });

        emit_reserve_stats(storage, dola_pool_id);
        emit_user_stats(storage, oracle, dola_pool_id, dola_user_id);
    }

    /// Turn collateral into liquid asset
    public(friend) fun cancel_as_collateral(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64,
        dola_pool_id: u16,
    ) {
        update_state(storage, clock, dola_pool_id);
        assert!(is_collateral(storage, dola_user_id, dola_pool_id), ENOT_COLLATERAL);

        storage::remove_user_collateral(storage, dola_user_id, dola_pool_id);
        storage::add_user_liquid_asset(storage, dola_user_id, dola_pool_id);

        // Check the freshness of the price
        check_user_fresh_price(oracle, storage, dola_user_id, clock);

        assert!(is_health(storage, oracle, dola_user_id), ENOT_HEALTH);
        update_interest_rate(pool_manager_info, storage, dola_pool_id, 0);
        update_average_liquidity(storage, oracle, clock, dola_user_id);

        event::emit(LendingCoreExecuteEvent {
            user_id: dola_user_id,
            amount: 0,
            pool_id: dola_pool_id,
            violator_id: 0,
            call_type: lending_codec::get_cancel_as_colleteral_type()
        });

        emit_reserve_stats(storage, dola_pool_id);
        emit_user_stats(storage, oracle, dola_pool_id, dola_user_id);
    }

    /// === Governance Functions ===

    /// Extract funds from the Treasury through governance
    public fun claim_from_treasury(
        _: &GovernanceCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
        receiver_id: u64,
        withdraw_amount: u256
    ) {
        update_state(storage, clock, dola_pool_id);
        let treasury_id = storage::get_reserve_treasury(storage, dola_pool_id);
        let treasury_amount = user_collateral_balance(storage, treasury_id, dola_pool_id);
        let deficit = user_loan_balance(storage, treasury_id, dola_pool_id);
        let treasury_avaliable_amount = if (treasury_amount > deficit) { treasury_amount - deficit } else { 0 };
        let amount = math::min(treasury_avaliable_amount, withdraw_amount);
        burn_otoken(storage, treasury_id, dola_pool_id, amount);
        mint_otoken(storage, receiver_id, dola_pool_id, amount);

        update_interest_rate(pool_manager_info, storage, dola_pool_id, 0);

        emit_reserve_stats(storage, dola_pool_id);
    }

    /// === Helper Functions ===

    public fun not_reach_supply_ceiling(storage: &mut Storage, dola_pool_id: u16, supply_amount: u256): bool {
        let supply_ceiling = storage::get_reserve_supply_ceiling(storage, dola_pool_id);
        let total_supply = total_otoken_supply(storage, dola_pool_id);
        supply_ceiling == 0 || total_supply + supply_amount < supply_ceiling
    }

    /// Check whether the maximum borrow limit has been reached
    public fun not_reach_borrow_ceiling(storage: &mut Storage, dola_user_id: u64, borrow_amount: u256): bool {
        let user_collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let isolate_asset = vector::borrow(&user_collaterals, 0);
        let borrow_ceiling = storage::get_reserve_borrow_ceiling(storage, *isolate_asset);
        let isolate_debt = storage::get_isolate_debt(storage, *isolate_asset);
        borrow_ceiling == 0 || isolate_debt + borrow_amount < borrow_ceiling
    }

    public fun is_borrowable_asset(storage: &mut Storage, dola_pool_id: u16): bool {
        storage::get_borrow_coefficient(storage, dola_pool_id) > 0
    }

    public fun is_health(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): bool {
        user_health_factor(storage, oracle, dola_user_id) > math::ray()
    }

    public fun is_liquid_asset(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        if (storage::exist_user_info(storage, dola_user_id)) {
            let liquid_assets = storage::get_user_liquid_assets(storage, dola_user_id);
            vector::contains(&liquid_assets, &dola_pool_id)
        } else {
            false
        }
    }

    public fun is_collateral(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        vector::contains(&collaterals, &dola_pool_id)
    }

    public fun is_loan(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        let loans = storage::get_user_loans(storage, dola_user_id);
        vector::contains(&loans, &dola_pool_id)
    }

    public fun is_isolation_mode(storage: &mut Storage, dola_user_id: u64): bool {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        if (vector::length(&collaterals) == 1) {
            let collateral = *vector::borrow(&collaterals, 0);
            storage::is_isolated_asset(storage, collateral)
        } else {
            false
        }
    }

    /// Check to see if these assets involved in calculating health factors have the latest prices.
    public fun check_user_fresh_price(
        price_oracle: &mut PriceOracle,
        storage: &mut Storage,
        dola_user_id: u64,
        clock: &Clock
    ) {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let loans = storage::get_user_loans(storage, dola_user_id);
        if (vector::length(&loans) > 0) {
            check_fresh_price(price_oracle, collaterals, clock);
            check_fresh_price(price_oracle, loans, clock);
        }
    }

    public fun has_collateral(storage: &mut Storage, dola_user_id: u64): bool {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        vector::length(&collaterals) > 0
    }

    /// If the user has a collateral value of 0 but still has debt, the system has a deficit.
    public fun has_deficit(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): bool {
        let user_collateral_value = user_total_collateral_value(storage, oracle, dola_user_id);
        let user_loan_value = user_total_loan_value(storage, oracle, dola_user_id);
        user_collateral_value == 0 && user_loan_value > 0
    }


    public fun user_health_factor(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): u256 {
        let health_collateral_value = user_health_collateral_value(storage, oracle, dola_user_id);
        let health_loan_value = user_health_loan_value(storage, oracle, dola_user_id);
        if (health_loan_value > 0) {
            math::ray_div((health_collateral_value), (health_loan_value))
        } else {
            U256_MAX
        }
    }

    public fun user_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let balance = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        calculate_value(oracle, dola_pool_id, balance)
    }

    public fun user_collateral_balance(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let scaled_balance = storage::get_user_scaled_otoken(storage, dola_user_id, dola_pool_id);
        let current_index = storage::get_liquidity_index(storage, dola_pool_id);
        scaled_balance::balance_of(scaled_balance, current_index)
    }

    public fun user_loan_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let balance = user_loan_balance(storage, dola_user_id, dola_pool_id);
        calculate_value(oracle, dola_pool_id, balance)
    }

    public fun user_loan_balance(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let scaled_balance = storage::get_user_scaled_dtoken(storage, dola_user_id, dola_pool_id);
        let current_index = storage::get_borrow_index(storage, dola_pool_id);
        scaled_balance::balance_of(scaled_balance, current_index)
    }

    public fun user_health_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u256 {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let length = vector::length(&collaterals);
        let value = 0;
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let collateral_coefficient = storage::get_collateral_coefficient(storage, *collateral);
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            value = value + math::ray_mul(collateral_value, collateral_coefficient);
            i = i + 1;
        };
        value
    }

    public fun user_health_loan_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u256 {
        let loans = storage::get_user_loans(storage, dola_user_id);
        let length = vector::length(&loans);
        let value = 0;
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let borrow_coefficient = storage::get_borrow_coefficient(storage, *loan);
            let loan_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            value = value + math::ray_mul(loan_value, borrow_coefficient);
            i = i + 1;
        };
        value
    }

    public fun user_total_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u256 {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let length = vector::length(&collaterals);
        let value = 0;
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            value = value + collateral_value;
            i = i + 1;
        };
        value
    }

    public fun user_total_loan_value(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): u256 {
        let loans = storage::get_user_loans(storage, dola_user_id);
        let length = vector::length(&loans);
        let value = 0;
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let loan_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            value = value + loan_value;
            i = i + 1;
        };
        value
    }

    public fun calculate_value(oracle: &mut PriceOracle, dola_pool_id: u16, amount: u256): u256 {
        let (price, decimal, _) = oracle::get_token_price(oracle, dola_pool_id);
        amount * price / (sui::math::pow(10, decimal) as u256)
    }

    public fun calculate_amount(oracle: &mut PriceOracle, dola_pool_id: u16, value: u256): u256 {
        let (price, decimal, _) = oracle::get_token_price(oracle, dola_pool_id);
        value * (sui::math::pow(10, decimal) as u256) / price
    }

    public fun calculate_liquidation_base_discount(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        violator: u64
    ): u256 {
        let health_collateral_value = user_health_collateral_value(storage, oracle, violator);
        let health_loan_value = user_health_loan_value(storage, oracle, violator);
        // health_collateral_value < health_loan_value
        math::ray() - math::ray_div(health_collateral_value, health_loan_value)
    }

    /// The liquidation discount is calculated based on the average
    /// liquidity of the user on the basis of the base discount.
    public fun calculate_liquidation_discount(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: u64,
        violator: u64
    ): u256 {
        assert!(storage::exist_user_info(storage, violator), ENOT_USER);
        assert!(storage::exist_user_info(storage, liquidator), ENOT_USER);
        let base_discount = calculate_liquidation_base_discount(storage, oracle, violator);
        let average_liquidity = storage::get_user_average_liquidity(storage, liquidator);
        let health_loan_value = user_health_loan_value(storage, oracle, violator);
        let discount_booster = math::ray_div(
            average_liquidity,
            5 * health_loan_value
        );
        discount_booster = math::min(discount_booster, math::ray()) + math::ray();
        let liquidation_discount = math::ray_mul(base_discount, discount_booster);
        math::min(liquidation_discount, MAX_DISCOUNT)
    }

    /// Calculate the maximum number of users that can be cleared based
    /// on the target health factor and clearing discount.
    ///
    /// The calculation details refer to:
    ///     [https://github.com/OmniBTC/DOLA-Protocol/tree/main/en#221-omnichain-lending:~:text=period%20of%20time.-,Liquidation,-Liquidation%20is%20when]
    public fun calculate_max_liquidation(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: u64,
        violator: u64,
        collateral: u16,
        loan: u16
    ): (u256, u256) {
        let liquidation_discount = calculate_liquidation_discount(
            storage,
            oracle,
            liquidator,
            violator,
        );

        let health_collateral_value = user_health_collateral_value(storage, oracle, violator);
        let health_loan_value = user_health_loan_value(storage, oracle, violator);

        let borrow_coefficient = storage::get_borrow_coefficient(storage, loan);
        let collateral_coefficient = storage::get_collateral_coefficient(storage, collateral);

        let target_health_value = math::ray_mul(
            health_loan_value,
            TARGET_HEALTH_FACTOR)
            - health_collateral_value;
        let target_coefficient = math::ray_mul(
            math::ray_mul(TARGET_HEALTH_FACTOR, math::ray() - liquidation_discount),
            borrow_coefficient
        ) - collateral_coefficient;

        let max_liquidable_collateral_value = math::ray_div(target_health_value, target_coefficient);
        let user_max_collateral_value = user_collateral_value(storage, oracle, violator, collateral);
        let collateral_ratio = math::ray_div(
            user_max_collateral_value,
            max_liquidable_collateral_value
        );

        let max_liquidable_debt_vaule = math::ray_mul(
            max_liquidable_collateral_value,
            math::ray() - liquidation_discount
        );
        let user_max_debt_value = user_loan_value(storage, oracle, violator, loan);
        let debt_ratio = math::ray_div(user_max_debt_value, max_liquidable_debt_vaule);

        let ratio = math::min(math::min(collateral_ratio, debt_ratio), math::ray());
        let max_liquidable_collateral = calculate_amount(
            oracle,
            collateral,
            math::ray_mul(max_liquidable_collateral_value, ratio)
        );
        let max_liquidable_debt = calculate_amount(
            oracle,
            loan,
            math::ray_mul(max_liquidable_debt_vaule, ratio)
        );
        (max_liquidable_collateral, max_liquidable_debt)
    }

    /// Determine the amount of collateral that can be liquidated based on the user's ability to repay.
    public fun calculate_actual_liquidation(
        oracle: &mut PriceOracle,
        collateral: u16,
        max_liquidable_collateral: u256,
        loan: u16,
        max_liquidable_debt: u256,
        repay_debt: u256,
        treasury_factor: u256
    ): (u256, u256, u256, u256) {
        let actual_liquidable_collateral;
        let actual_liquidable_debt;

        if (repay_debt >= max_liquidable_debt) {
            actual_liquidable_debt = max_liquidable_debt;
            actual_liquidable_collateral = max_liquidable_collateral;
        } else {
            actual_liquidable_debt = repay_debt;
            actual_liquidable_collateral = math::ray_mul(
                (max_liquidable_collateral),
                math::ray_div(actual_liquidable_debt, max_liquidable_debt)
            );
        };

        let collateral_value = calculate_value(oracle, collateral, actual_liquidable_collateral);
        let loan_value = calculate_value(oracle, loan, actual_liquidable_debt);
        let reward = calculate_amount(oracle, collateral, collateral_value - loan_value);
        // the treasury keeps a portion of the discount incentive
        let treasury_reserved_collateral = math::ray_mul(reward, treasury_factor);
        let liquidator_acquired_collateral = actual_liquidable_collateral - treasury_reserved_collateral;
        (actual_liquidable_collateral, actual_liquidable_debt, liquidator_acquired_collateral, treasury_reserved_collateral)
    }

    public fun total_otoken_supply(storage: &mut Storage, dola_pool_id: u16): u256 {
        let scaled_total_otoken_supply = storage::get_otoken_scaled_total_supply(storage, dola_pool_id);
        let current_index = storage::get_liquidity_index(storage, dola_pool_id);
        math::ray_mul((scaled_total_otoken_supply), current_index)
    }

    public fun total_dtoken_supply(storage: &mut Storage, dola_pool_id: u16): u256 {
        let scaled_total_dtoken_supply = storage::get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let current_index = storage::get_borrow_index(storage, dola_pool_id);
        math::ray_mul((scaled_total_dtoken_supply), current_index)
    }

    /// === Internal Functions ===

    /// If the user is liquidated and still has debts, transfer his debts to the Treasury,
    /// which will cover his debts.
    fun cover_deficit(storage: &mut Storage, dola_user_id: u64) {
        let loans = storage::get_user_loans(storage, dola_user_id);
        let length = vector::length(&loans);
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let treasury = storage::get_reserve_treasury(storage, *loan);
            let debt = user_loan_balance(storage, dola_user_id, *loan);
            // Transfer deficits to treasury debt
            burn_dtoken(storage, dola_user_id, *loan, debt);
            mint_dtoken(storage, treasury, *loan, debt);
            i = i + 1;
        };
    }

    fun mint_otoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u256,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(
            token_amount,
            storage::get_liquidity_index(storage, dola_pool_id)
        );
        storage::mint_otoken_scaled(
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    fun burn_otoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u256,
    ) {
        let scaled_amount = scaled_balance::burn_scaled(
            token_amount,
            storage::get_liquidity_index(storage, dola_pool_id)
        );
        storage::burn_otoken_scaled(
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    fun mint_dtoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u256,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, storage::get_borrow_index(storage, dola_pool_id));
        storage::mint_dtoken_scaled(
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    fun burn_dtoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u256,
    ) {
        let scaled_amount = scaled_balance::burn_scaled(token_amount, storage::get_borrow_index(storage, dola_pool_id));
        storage::burn_dtoken_scaled(
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    fun add_isolate_debt(
        storage: &mut Storage,
        dola_user_id: u64,
        amount: u256,
    ) {
        let user_collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let isolate_asset = vector::borrow(&user_collaterals, 0);
        let isolate_debt = storage::get_isolate_debt(storage, *isolate_asset);
        let new_isolate_debt = isolate_debt + amount;
        storage::update_isolate_debt(storage, *isolate_asset, new_isolate_debt)
    }

    fun reduce_isolate_debt(
        storage: &mut Storage,
        dola_user_id: u64,
        amount: u256,
    ) {
        let user_collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let isolate_asset = vector::borrow(&user_collaterals, 0);
        let isolate_debt = storage::get_isolate_debt(storage, *isolate_asset);
        let new_isolate_debt = if (isolate_debt >= amount) {
            isolate_debt - amount
        } else {
            0
        };
        storage::update_isolate_debt(storage, *isolate_asset, new_isolate_debt)
    }

    /// Update the average liquidity of user
    fun update_average_liquidity(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64
    ) {
        if (storage::exist_user_info(storage, dola_user_id)) {
            let current_timestamp = storage::get_timestamp(clock);
            let last_update_timestamp = storage::get_user_last_timestamp(storage, dola_user_id);
            let health_collateral_value = user_health_collateral_value(storage, oracle, dola_user_id);
            let health_loan_value = user_health_loan_value(storage, oracle, dola_user_id);
            if (health_collateral_value > health_loan_value) {
                let health_value = health_collateral_value - health_loan_value;
                let average_liquidity = storage::get_user_average_liquidity(storage, dola_user_id);
                let new_average_liquidity = rates::calculate_average_liquidity(
                    current_timestamp,
                    last_update_timestamp,
                    average_liquidity,
                    health_value
                );
                storage::update_user_average_liquidity(storage, clock, dola_user_id, new_average_liquidity);
            } else {
                storage::update_user_average_liquidity(storage, clock, dola_user_id, 0);
            }
        }
    }

    /// Update the index and deposit a portion of the interest into the Treasury
    ///
    /// More details refer to:
    ///    [https://github.com/OmniBTC/DOLA-Protocol/tree/main/en#221-omnichain-lending:~:text=users%20to%20operate.-,Interest%20Rate%20Model,-Reserves%3A%20In%20lending]
    fun update_state(
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
    ) {
        let current_timestamp = storage::get_timestamp(clock);

        let last_update_timestamp = storage::get_last_update_timestamp(storage, dola_pool_id);
        let dtoken_scaled_total_supply = storage::get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let current_borrow_index = storage::get_borrow_index(storage, dola_pool_id);
        let current_liquidity_index = storage::get_liquidity_index(storage, dola_pool_id);

        let treasury_factor = storage::get_treasury_factor(storage, dola_pool_id);

        let new_borrow_index = math::ray_mul(rates::calculate_compounded_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_borrow_rate(storage, dola_pool_id)
        ), current_borrow_index);

        let new_liquidity_index = math::ray_mul(rates::calculate_linear_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_liquidity_rate(storage, dola_pool_id)
        ), current_liquidity_index);

        let mint_to_treasury = math::ray_mul(
            math::ray_mul(dtoken_scaled_total_supply, (new_borrow_index - current_borrow_index)),
            treasury_factor
        );
        let mint_to_treasury_scaled = scaled_balance::mint_scaled(
            mint_to_treasury,
            new_liquidity_index
        );
        storage::update_state(
            storage,
            dola_pool_id,
            new_borrow_index,
            new_liquidity_index,
            current_timestamp,
            mint_to_treasury_scaled
        );
    }

    /// Update the interest rate on the reserve
    ///
    /// More details refer to:
    ///     [https://github.com/OmniBTC/DOLA-Protocol/tree/main/en#221-omnichain-lending:~:text=users%20to%20operate.-,Interest%20Rate%20Model,-Reserves%3A%20In%20lending]
    fun update_interest_rate(
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16,
        reduced_liquidity: u256
    ) {
        let liquidity = pool_manager::get_app_liquidity(
            pool_manager_info,
            dola_pool_id,
            storage::get_app_id(storage)
        );
        assert!(liquidity >= (reduced_liquidity), ENOT_ENOUGH_LIQUIDITY);
        // Since the removed liquidity is later, it needs to be calculated with the updated liquidity
        let liquidity = liquidity - reduced_liquidity;
        let borrow_rate = rates::calculate_borrow_rate(storage, dola_pool_id, liquidity);
        let liquidity_rate = rates::calculate_liquidity_rate(storage, dola_pool_id, borrow_rate, liquidity);
        storage::update_interest_rate(storage, dola_pool_id, borrow_rate, liquidity_rate);
    }

    #[test_only]
    public fun update_state_for_testing(
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
    ) {
        update_state(
            storage,
            clock,
            dola_pool_id
        );
    }

    #[test_only]
    public fun update_average_liquidity_for_testing(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        dola_user_id: u64
    ) {
        update_average_liquidity(
            storage,
            oracle,
            clock,
            dola_user_id
        );
    }
}
