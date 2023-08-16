// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::lending_core_storage {
    use std::vector;

    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::app_manager::{Self, AppCap, TotalAppInfo};
    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::ray_math as math;

    friend dola_protocol::lending_logic;
    friend dola_protocol::lending_portal;
    friend dola_protocol::lending_core_wormhole_adapter;

    /// Errors

    const EALREADY_EXIST_RESERVE: u64 = 0;

    const EAMOUNT_NOT_ENOUGH: u64 = 1;

    struct Storage has key {
        id: UID,
        /// Used in representative lending app
        app_cap: AppCap,
        // Dola pool id -> reserve data
        reserves: Table<u16, ReserveData>,
        // Dola user id -> user info
        user_infos: Table<u64, UserInfo>
    }

    struct UserInfo has store {
        // Average liquidity
        average_liquidity: u256,
        // Timestamp of last update average
        last_average_update: u256,
        // Tokens as liquid assets, they can still capture the yield but won't be able to use it as collateral
        liquid_assets: vector<u16>,
        // Tokens as collateral, such as ETH, BTC etc. Represent by dola_pool_id.
        collaterals: vector<u16>,
        // Tokens as loan, such as USDT, USDC, DAI etc. Represent by dola_pool_id.
        loans: vector<u16>
    }

    struct ReserveData has store {
        // Is it a isolated asset
        is_isolated_asset: bool,
        // Enable borrow when isolation
        borrowable_in_isolation: bool,
        // Accumulated isolate debt
        isolate_debt: u256,
        // Timestamp of last update
        last_update_timestamp: u256,
        // Treasury (dola_user_id)
        treasury: u64,
        // Treasury interest factor [math::ray]
        treasury_factor: u256,
        // Supply cap ceiling, 0 means there is no ceiling
        supply_cap_ceiling: u256,
        // Borrow cap ceiling, 0 means there is no ceiling
        borrow_cap_ceiling: u256,
        // Current borrow rate [math::ray]
        current_borrow_rate: u256,
        // Current supply rate [math::ray]
        current_liquidity_rate: u256,
        // Current borrow index [math::ray]
        current_borrow_index: u256,
        // Current liquidity index [math::ray]
        current_liquidity_index: u256,
        // Collateral coefficient [math::ray]
        collateral_coefficient: u256,
        // Borrow coefficient [math::ray]
        borrow_coefficient: u256,
        // Borrow rate factors, for borrow rate calculation
        borrow_rate_factors: BorrowRateFactors,
        // ScaledBalance for oToken
        otoken_scaled: ScaledBalance,
        // ScaledBalance for dToken
        dtoken_scaled: ScaledBalance,
    }

    struct ScaledBalance has store {
        // dola_user_id address => scale balance
        user_state: Table<u64, u256>,
        // total supply of scale balance
        total_supply: u256,
    }

    struct BorrowRateFactors has store {
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256
    }

    /// === Initial Functions ===

    public fun initialize_cap_with_governance(
        governance: &GovernanceCap,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            app_cap: app_manager::register_cap_with_governance(governance, total_app_info, ctx),
            reserves: table::new(ctx),
            user_infos: table::new(ctx)
        });
    }

    /// === Governance Functions ===

    public fun register_new_reserve(
        _: &GovernanceCap,
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
        is_isolated_asset: bool,
        borrowable_in_isolation: bool,
        treasury: u64,
        treasury_factor: u256,
        supply_cap_ceiling: u256,
        borrow_cap_ceiling: u256,
        collateral_coefficient: u256,
        borrow_coefficient: u256,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256,
        ctx: &mut TxContext
    ) {
        assert!(!table::contains(&storage.reserves, dola_pool_id), EALREADY_EXIST_RESERVE);
        table::add(&mut storage.reserves, dola_pool_id, ReserveData {
            is_isolated_asset,
            borrowable_in_isolation,
            isolate_debt: 0,
            last_update_timestamp: get_timestamp(clock),
            treasury,
            treasury_factor,
            supply_cap_ceiling,
            borrow_cap_ceiling,
            current_borrow_rate: 0,
            current_liquidity_rate: 0,
            current_borrow_index: math::ray(),
            current_liquidity_index: math::ray(),
            collateral_coefficient,
            borrow_coefficient,
            borrow_rate_factors: BorrowRateFactors {
                base_borrow_rate,
                borrow_rate_slope1,
                borrow_rate_slope2,
                optimal_utilization
            },
            otoken_scaled: ScaledBalance {
                user_state: table::new<u64, u256>(ctx),
                total_supply: 0,
            },
            dtoken_scaled: ScaledBalance {
                user_state: table::new<u64, u256>(ctx),
                total_supply: 0,
            },
        });
    }

    public fun set_is_isolated_asset(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        is_isolated_asset: bool
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.is_isolated_asset = is_isolated_asset;
    }

    public fun set_borrowable_in_isolation(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        borrowable_in_isolation: bool
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.borrowable_in_isolation = borrowable_in_isolation;
    }

    public fun set_treasury_factor(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        treasury_factor: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.treasury_factor = treasury_factor;
    }

    public fun set_supply_cap_ceiling(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        supply_cap_ceiling: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.supply_cap_ceiling = supply_cap_ceiling;
    }

    public fun set_borrow_cap_ceiling(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        borrow_cap_ceiling: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.borrow_cap_ceiling = borrow_cap_ceiling;
    }

    public fun set_collateral_coefficient(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        collateral_coefficient: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.collateral_coefficient = collateral_coefficient;
    }

    public fun set_borrow_coefficient(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        borrow_coefficient: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.borrow_coefficient = borrow_coefficient;
    }

    public fun set_borrow_rate_factors(
        _: &GovernanceCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256
    ) {
        let borrow_rate_factors = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).borrow_rate_factors;
        borrow_rate_factors.base_borrow_rate = base_borrow_rate;
        borrow_rate_factors.borrow_rate_slope1 = borrow_rate_slope1;
        borrow_rate_factors.borrow_rate_slope2 = borrow_rate_slope2;
        borrow_rate_factors.optimal_utilization = optimal_utilization;
    }

    /// === View Functions ===

    public fun borrow_storage_id(storage: &Storage): &UID {
        &storage.id
    }

    public fun get_storage_id(storage: &mut Storage): &mut UID {
        &mut storage.id
    }

    public fun get_app_id(
        storage: &mut Storage
    ): u16 {
        app_manager::get_app_id(&storage.app_cap)
    }

    public fun get_timestamp(sui_clock: &Clock): u256 {
        ((clock::timestamp_ms(sui_clock) / 1000) as u256)
    }

    public fun is_isolated_asset(storage: &mut Storage, dola_pool_id: u16): bool {
        table::borrow(&storage.reserves, dola_pool_id).is_isolated_asset
    }

    public fun can_borrow_in_isolation(storage: &mut Storage, dola_pool_id: u16): bool {
        table::borrow(&storage.reserves, dola_pool_id).borrowable_in_isolation
    }

    public fun get_reserve_length(storage: &mut Storage): u64 {
        table::length(&storage.reserves)
    }

    public fun exist_user_info(storage: &mut Storage, dola_user_id: u64): bool {
        table::contains(&mut storage.user_infos, dola_user_id)
    }

    public fun exist_reserve(storage: &mut Storage, dola_pool_id: u16): bool {
        table::contains(&mut storage.reserves, dola_pool_id)
    }

    public fun get_user_last_timestamp(storage: &mut Storage, dola_user_id: u64): u256 {
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.last_average_update
    }

    public fun get_user_average_liquidity(storage: &mut Storage, dola_user_id: u64): u256 {
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.average_liquidity
    }

    public fun get_user_liquid_assets(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.liquid_assets
    }

    public fun get_user_collaterals(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.collaterals
    }

    public fun get_user_loans(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.loans
    }

    public fun get_user_scaled_otoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let reserve = table::borrow(&storage.reserves, dola_pool_id);
        if (table::contains(&reserve.otoken_scaled.user_state, dola_user_id)) {
            *table::borrow(&reserve.otoken_scaled.user_state, dola_user_id)
        } else {
            0
        }
    }

    public fun get_user_scaled_dtoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let reserve = table::borrow(&storage.reserves, dola_pool_id);
        if (table::contains(&reserve.dtoken_scaled.user_state, dola_user_id)) {
            *table::borrow(&reserve.dtoken_scaled.user_state, dola_user_id)
        } else {
            0
        }
    }

    public fun get_user_scaled_otoken_v2(
        storage: &Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let reserve = table::borrow(&storage.reserves, dola_pool_id);
        if (table::contains(&reserve.otoken_scaled.user_state, dola_user_id)) {
            *table::borrow(&reserve.otoken_scaled.user_state, dola_user_id)
        } else {
            0
        }
    }

    public fun get_user_scaled_dtoken_v2(
        storage: &Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u256 {
        let reserve = table::borrow(&storage.reserves, dola_pool_id);
        if (table::contains(&reserve.dtoken_scaled.user_state, dola_user_id)) {
            *table::borrow(&reserve.dtoken_scaled.user_state, dola_user_id)
        } else {
            0
        }
    }

    public fun get_reserve_treasury(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u64 {
        table::borrow(&storage.reserves, dola_pool_id).treasury
    }

    public fun get_isolate_debt(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).isolate_debt
    }

    public fun get_treasury_factor(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).treasury_factor
    }

    public fun get_reserve_supply_ceiling(storage: &mut Storage, dola_pool_id: u16): u256 {
        table::borrow(&storage.reserves, dola_pool_id).supply_cap_ceiling
    }

    public fun get_reserve_borrow_ceiling(storage: &mut Storage, dola_pool_id: u16): u256 {
        table::borrow(&storage.reserves, dola_pool_id).borrow_cap_ceiling
    }

    public fun get_borrow_coefficient(storage: &mut Storage, dola_pool_id: u16): u256 {
        table::borrow(&storage.reserves, dola_pool_id).borrow_coefficient
    }

    public fun get_collateral_coefficient(storage: &mut Storage, dola_pool_id: u16): u256 {
        table::borrow(&storage.reserves, dola_pool_id).collateral_coefficient
    }

    public fun get_last_update_timestamp(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).last_update_timestamp
    }

    public fun get_otoken_scaled_total_supply(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).otoken_scaled.total_supply
    }

    public fun get_dtoken_scaled_total_supply(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).dtoken_scaled.total_supply
    }

    public fun get_otoken_scaled_total_supply_v2(
        storage: &Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).otoken_scaled.total_supply
    }

    public fun get_dtoken_scaled_total_supply_v2(
        storage: &Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).dtoken_scaled.total_supply
    }

    public fun get_liquidity_rate(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).current_liquidity_rate
    }

    public fun get_liquidity_index(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).current_liquidity_index
    }

    public fun get_borrow_rate(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).current_borrow_rate
    }

    public fun get_borrow_index(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        table::borrow(&storage.reserves, dola_pool_id).current_borrow_index
    }

    public fun get_borrow_rate_factors(
        storage: &mut Storage,
        dola_pool_id: u16
    ): (u256, u256, u256, u256) {
        let borrow_rate_factors = &table::borrow(&storage.reserves, dola_pool_id).borrow_rate_factors;
        (borrow_rate_factors.base_borrow_rate, borrow_rate_factors.borrow_rate_slope1, borrow_rate_factors.borrow_rate_slope2, borrow_rate_factors.optimal_utilization)
    }

    /// === Friend Functions ===

    public(friend) fun get_app_cap(
        storage: &mut Storage
    ): &AppCap {
        &storage.app_cap
    }

    public(friend) fun mint_otoken_scaled(
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u256
    ) {
        let otoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).otoken_scaled;
        let current_amount;

        if (table::contains(&otoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut otoken_scaled.user_state, dola_user_id);
        }else {
            current_amount = 0
        };
        table::add(&mut otoken_scaled.user_state, dola_user_id, scaled_amount + current_amount);
        otoken_scaled.total_supply = otoken_scaled.total_supply + scaled_amount;
    }

    public(friend) fun burn_otoken_scaled(
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u256
    ) {
        let otoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).otoken_scaled;
        let current_amount;

        if (table::contains(&otoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut otoken_scaled.user_state, dola_user_id);
        } else {
            current_amount = 0
        };
        assert!(current_amount >= scaled_amount, EAMOUNT_NOT_ENOUGH);
        table::add(&mut otoken_scaled.user_state, dola_user_id, current_amount - scaled_amount);
        otoken_scaled.total_supply = otoken_scaled.total_supply - scaled_amount;
    }

    public(friend) fun mint_dtoken_scaled(
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u256
    ) {
        let dtoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).dtoken_scaled;
        let current_amount;

        if (table::contains(&dtoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut dtoken_scaled.user_state, dola_user_id);
        }else {
            current_amount = 0
        };
        table::add(&mut dtoken_scaled.user_state, dola_user_id, scaled_amount + current_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply + scaled_amount;
    }

    public(friend) fun burn_dtoken_scaled(
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u256
    ) {
        let dtoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).dtoken_scaled;
        let current_amount;

        if (table::contains(&dtoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut dtoken_scaled.user_state, dola_user_id);
        } else {
            current_amount = 0
        };
        assert!(current_amount >= scaled_amount, EAMOUNT_NOT_ENOUGH);
        table::add(&mut dtoken_scaled.user_state, dola_user_id, current_amount - scaled_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply - scaled_amount;
    }

    /// Ensure that the collateral and liquid assets are not duplicated
    public(friend) fun add_user_liquid_asset(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        if (!vector::contains(&user_info.liquid_assets, &dola_pool_id) &&
            !vector::contains(&user_info.collaterals, &dola_pool_id)
        ) {
            vector::push_back(&mut user_info.liquid_assets, dola_pool_id)
        }
    }

    public(friend) fun remove_user_liquid_asset(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);

        let (exist, index) = vector::index_of(&user_info.liquid_assets, &dola_pool_id);

        if (exist) {
            vector::remove(&mut user_info.liquid_assets, index);
        }
    }

    /// Ensure that the collateral and liquid assets are not duplicated
    public(friend) fun add_user_collateral(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        if (!vector::contains(&user_info.collaterals, &dola_pool_id) &&
            !vector::contains(&user_info.liquid_assets, &dola_pool_id)
        ) {
            vector::push_back(&mut user_info.collaterals, dola_pool_id)
        }
    }

    public(friend) fun remove_user_collateral(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);

        let (exist, index) = vector::index_of(&user_info.collaterals, &dola_pool_id);
        if (exist) {
            vector::remove(&mut user_info.collaterals, index);
        }
    }

    public(friend) fun add_user_loan(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        if (!vector::contains(&user_info.loans, &dola_pool_id)) {
            vector::push_back(&mut user_info.loans, dola_pool_id)
        }
    }

    public(friend) fun remove_user_loan(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);

        let (exist, index) = vector::index_of(&user_info.loans, &dola_pool_id);
        if (exist) {
            vector::remove(&mut user_info.loans, index);
        }
    }

    public(friend) fun update_user_average_liquidity(
        storage: &mut Storage,
        clock: &Clock,
        dola_user_id: u64,
        average_liquidity: u256
    ) {
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        user_info.last_average_update = get_timestamp(clock);
        user_info.average_liquidity = average_liquidity;
    }

    public(friend) fun update_isolate_debt(
        storage: &mut Storage,
        dola_pool_id: u16,
        isolate_debt: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.isolate_debt = isolate_debt;
    }

    public(friend) fun update_state(
        storage: &mut Storage,
        dola_pool_id: u16,
        new_borrow_index: u256,
        new_liquidity_index: u256,
        last_update_timestamp: u256,
        mint_to_treasury_scaled: u256
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.current_borrow_index = new_borrow_index;
        reserve.current_liquidity_index = new_liquidity_index;
        reserve.last_update_timestamp = last_update_timestamp;

        // Mint to treasury
        let dola_treasury_id = table::borrow(&storage.reserves, dola_pool_id).treasury;
        mint_otoken_scaled(
            storage,
            dola_pool_id,
            dola_treasury_id,
            mint_to_treasury_scaled
        );
    }

    public(friend) fun update_interest_rate(
        storage: &mut Storage,
        dola_pool_id: u16,
        new_borrow_rate: u256,
        new_liquidity_rate: u256,
    ) {
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.current_borrow_rate = new_borrow_rate;
        reserve.current_liquidity_rate = new_liquidity_rate;
    }

    /// === Helper Functions ===

    public fun ensure_user_info_exist(
        storage: &mut Storage,
        clock: &Clock,
        dola_user_id: u64,
    ) {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
                average_liquidity: 0,
                last_average_update: get_timestamp(clock),
                liquid_assets: vector::empty(),
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
    }

    #[test_only]
    public fun init_for_testing(app_cap: AppCap, ctx: &mut TxContext) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            app_cap,
            reserves: table::new(ctx),
            user_infos: table::new(ctx)
        });
    }
}
