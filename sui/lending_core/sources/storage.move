module lending_core::storage {
    use std::option::{Self, Option};
    use std::vector;

    use app_manager::app_manager::{Self, AppCap};
    use governance::genesis::GovernanceCap;
    use oracle::oracle::{Self, PriceOracle};
    use ray_math::math;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const EONLY_ONE_ADMIN: u64 = 0;

    const EALREADY_EXIST_RESERVE: u64 = 1;

    const ENONEXISTENT_RESERVE: u64 = 2;

    const ENONEXISTENT_USERINFO: u64 = 3;

    const EMUST_NONE: u64 = 4;

    const EMUST_SOME: u64 = 5;

    const EAMOUNT_NOT_ENOUGH: u64 = 6;

    struct Storage has key {
        id: UID,
        app_cap: Option<AppCap>,
        // Token category -> reserve data
        reserves: Table<u16, ReserveData>,
        // Dola user id -> user info
        user_infos: Table<u64, UserInfo>
    }

    struct UserInfo has store {
        // Average liquidity
        average_liquidity: u64,
        // Timestamp of last update
        last_update_timestamp: u64,
        // Tokens as collateral, such as ETH, BTC etc. Represent by dola_pool_id.
        collaterals: vector<u16>,
        // Tokens as loan, such as USDT, USDC, DAI etc. Represent by dola_pool_id.
        loans: vector<u16>
    }

    struct ReserveData has store {
        // Teserve flag
        // todo! add some flags
        flag: bool,
        // Timestamp of last update
        // todo: use sui timestamp
        last_update_timestamp: u64,
        // Treasury (dola_user_id)
        treasury: u64,
        // Treasury interest factor [math::ray]
        treasury_factor: u256,
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
        user_state: Table<u64, u64>,
        // total supply of scale balance
        total_supply: u128,
    }

    struct BorrowRateFactors has store {
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256
    }

    struct StorageCap has store, drop {}


    fun init(ctx: &mut TxContext) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            app_cap: option::none(),
            reserves: table::new(ctx),
            user_infos: table::new(ctx)
        });
    }

    public fun register_cap_with_governance(_: &GovernanceCap): StorageCap {
        StorageCap {}
    }

    public fun transfer_app_cap(
        storage: &mut Storage,
        app_cap: AppCap
    ) {
        assert!(option::is_none(&storage.app_cap), EMUST_NONE);
        option::fill(&mut storage.app_cap, app_cap);
    }

    public fun get_app_id(
        storage: &mut Storage
    ): u16 {
        app_manager::get_app_id(option::borrow(&storage.app_cap))
    }

    public fun get_app_cap(
        _: &StorageCap,
        storage: &mut Storage
    ): &AppCap {
        option::borrow(&storage.app_cap)
    }

    public fun register_new_reserve(
        _: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        treasury: u64,
        treasury_factor: u256,
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
            flag: true,
            last_update_timestamp: oracle::get_timestamp(oracle),
            treasury,
            treasury_factor,
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
                user_state: table::new<u64, u64>(ctx),
                total_supply: 0,
            },
            dtoken_scaled: ScaledBalance {
                user_state: table::new<u64, u64>(ctx),
                total_supply: 0,
            },
        });
    }

    public fun get_reserve_length(storage: &mut Storage): u64 {
        table::length(&storage.reserves)
    }

    public fun exist_user_info(storage: &mut Storage, dola_user_id: u64): bool {
        table::contains(&mut storage.user_infos, dola_user_id)
    }

    public fun get_user_last_timestamp(storage: &mut Storage, dola_user_id: u64): u64 {
        if (exist_user_info(storage, dola_user_id)) {
            let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
            user_info.last_update_timestamp
        } else { 0 }
    }

    public fun get_user_average_liquidity(storage: &mut Storage, dola_user_id: u64): u64 {
        if (exist_user_info(storage, dola_user_id)) {
            let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
            user_info.average_liquidity
        }
        else { 0 }
    }

    public fun get_user_collaterals(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        assert!(table::contains(&mut storage.user_infos, dola_user_id), ENONEXISTENT_USERINFO);
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.collaterals
    }

    public fun get_user_loans(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        assert!(table::contains(&mut storage.user_infos, dola_user_id), ENONEXISTENT_USERINFO);
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.loans
    }

    public fun get_user_scaled_otoken(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
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
    ): u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
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
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).treasury
    }

    public fun get_treasury_factor(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).treasury_factor
    }

    public fun get_borrow_coefficient(storage: &mut Storage, dola_pool_id: u16): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).borrow_coefficient
    }

    public fun get_collateral_coefficient(storage: &mut Storage, dola_pool_id: u16): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).collateral_coefficient
    }

    public fun get_last_update_timestamp(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u64 {
        // todo! too much judge contains
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).last_update_timestamp
    }

    public fun get_otoken_scaled_total_supply(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u128 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).otoken_scaled.total_supply
    }

    public fun get_dtoken_scaled_total_supply(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u128 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).dtoken_scaled.total_supply
    }

    public fun get_liquidity_rate(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_liquidity_rate
    }

    public fun get_liquidity_index(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_liquidity_index
    }

    public fun get_borrow_rate(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_borrow_rate
    }

    public fun get_borrow_index(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u256 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_borrow_index
    }

    public fun get_borrow_rate_factors(
        storage: &mut Storage,
        dola_pool_id: u16
    ): (u256, u256, u256, u256) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let borrow_rate_factors = &table::borrow(&storage.reserves, dola_pool_id).borrow_rate_factors;
        (borrow_rate_factors.base_borrow_rate, borrow_rate_factors.borrow_rate_slope1, borrow_rate_factors.borrow_rate_slope2, borrow_rate_factors.optimal_utilization)
    }

    public fun mint_otoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let otoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).otoken_scaled;
        let current_amount;

        if (table::contains(&otoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut otoken_scaled.user_state, dola_user_id);
        }else {
            current_amount = 0
        };
        table::add(&mut otoken_scaled.user_state, dola_user_id, scaled_amount + current_amount);
        otoken_scaled.total_supply = otoken_scaled.total_supply + (scaled_amount as u128);
    }

    public fun burn_otoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let otoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).otoken_scaled;
        let current_amount;

        if (table::contains(&otoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut otoken_scaled.user_state, dola_user_id);
        } else {
            current_amount = 0
        };
        assert!(current_amount >= scaled_amount, EAMOUNT_NOT_ENOUGH);
        table::add(&mut otoken_scaled.user_state, dola_user_id, current_amount - scaled_amount);
        otoken_scaled.total_supply = otoken_scaled.total_supply - (scaled_amount as u128);
    }

    public fun mint_dtoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let dtoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).dtoken_scaled;
        let current_amount;

        if (table::contains(&dtoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut dtoken_scaled.user_state, dola_user_id);
        }else {
            current_amount = 0
        };
        table::add(&mut dtoken_scaled.user_state, dola_user_id, scaled_amount + current_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply + (scaled_amount as u128);
    }

    public fun burn_dtoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        dola_user_id: u64,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let dtoken_scaled = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).dtoken_scaled;
        let current_amount;

        if (table::contains(&dtoken_scaled.user_state, dola_user_id)) {
            current_amount = table::remove(&mut dtoken_scaled.user_state, dola_user_id);
        } else {
            current_amount = 0
        };
        assert!(current_amount >= scaled_amount, EAMOUNT_NOT_ENOUGH);
        table::add(&mut dtoken_scaled.user_state, dola_user_id, current_amount - scaled_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply - (scaled_amount as u128);
    }

    public fun add_user_collateral(
        _: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
                average_liquidity: 0,
                last_update_timestamp: oracle::get_timestamp(oracle),
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        if (!vector::contains(&user_info.collaterals, &dola_pool_id)) {
            vector::push_back(&mut user_info.collaterals, dola_pool_id)
        }
    }

    public fun remove_user_collateral(
        _: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        assert!(table::contains(&mut storage.user_infos, dola_user_id), ENONEXISTENT_USERINFO);
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);

        let (exist, index) = vector::index_of(&user_info.collaterals, &dola_pool_id);
        if (exist) {
            let _ = vector::remove(&mut user_info.collaterals, index);
        }
    }

    public fun add_user_loan(
        _: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
                average_liquidity: 0,
                last_update_timestamp: oracle::get_timestamp(oracle),
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        if (!vector::contains(&user_info.loans, &dola_pool_id)) {
            vector::push_back(&mut user_info.loans, dola_pool_id)
        }
    }

    public fun remove_user_loan(
        _: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        assert!(table::contains(&mut storage.user_infos, dola_user_id), ENONEXISTENT_USERINFO);
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);

        let (exist, index) = vector::index_of(&user_info.loans, &dola_pool_id);
        if (exist) {
            let _ = vector::remove(&mut user_info.loans, index);
        }
    }

    public fun update_borrow_rate_factors(
        _: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let borrow_rate_factors = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).borrow_rate_factors;
        borrow_rate_factors.base_borrow_rate = base_borrow_rate;
        borrow_rate_factors.borrow_rate_slope1 = borrow_rate_slope1;
        borrow_rate_factors.borrow_rate_slope2 = borrow_rate_slope2;
        borrow_rate_factors.optimal_utilization = optimal_utilization;
    }

    public fun update_user_average_liquidity(
        _: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        average_liquidity: u64
    ) {
        assert!(table::contains(&mut storage.user_infos, dola_user_id), ENONEXISTENT_USERINFO);
        let user_info = table::borrow_mut(&mut storage.user_infos, dola_user_id);
        user_info.last_update_timestamp = oracle::get_timestamp(oracle);
        user_info.average_liquidity = average_liquidity;
    }

    public fun update_state(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        new_borrow_index: u256,
        new_liquidity_index: u256,
        last_update_timestamp: u64,
        mint_to_treasury_scaled: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.current_borrow_index = new_borrow_index;
        reserve.current_liquidity_index = new_liquidity_index;
        reserve.last_update_timestamp = last_update_timestamp;

        // Mint to treasury
        let dola_user_id = table::borrow(&storage.reserves, dola_pool_id).treasury;
        mint_otoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            mint_to_treasury_scaled
        );
    }

    public fun update_interest_rate(
        _: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        new_borrow_rate: u256,
        new_liquidity_rate: u256,
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.current_borrow_rate = new_borrow_rate;
        reserve.current_liquidity_rate = new_liquidity_rate;
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun register_storage_cap_for_testing(): StorageCap {
        StorageCap {}
    }
}
