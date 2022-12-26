module lending::storage {
    use std::option::{Self, Option};
    use std::vector;

    use app_manager::app_manager::{Self, AppCap};
    use governance::governance::GovernanceCap;
    use oracle::oracle::{PriceOracle, get_timestamp};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const RAY: u64 = 100000000;

    const EONLY_ONE_ADMIN: u64 = 0;

    const EALREADY_EXIST_RESERVE: u64 = 1;

    const ENONEXISTENT_RESERVE: u64 = 2;

    const ENONEXISTENT_USERINFO: u64 = 3;

    const EMUST_NONE: u64 = 4;

    const EMUST_SOME: u64 = 5;

    const ENOT_ENOUGH_AMOUNT: u64 = 6;

    struct Storage has key {
        id: UID,
        app_cap: Option<AppCap>,
        // token category -> reserve data
        reserves: Table<u16, ReserveData>,
        // dola dola_user_id id -> dola_user_id info
        user_infos: Table<u64, UserInfo>
    }

    struct UserInfo has store {
        // tokens as collateral, such as ETH, BTC etc. Represent by dola_pool_id.
        collaterals: vector<u16>,
        // tokens as loan, such as USDT, USDC, DAI etc. Represent by dola_pool_id.
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
        // Treasury interest factor
        treasury_factor: u64,
        // Current borrow rate.
        current_borrow_rate: u64,
        // Current supply rate.
        current_liquidity_rate: u64,
        // Current borrow index.
        current_borrow_index: u64,
        // Current liquidity index.
        current_liquidity_index: u64,
        // Collateral coefficient
        collateral_coefficient: u64,
        // Borrow coefficient
        borrow_coefficient: u64,
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
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64
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
        app_manager::app_id(option::borrow(&storage.app_cap))
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
        treasury_factor: u64,
        collateral_coefficient: u64,
        borrow_coefficient: u64,
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64,
        ctx: &mut TxContext
    ) {
        assert!(!table::contains(&storage.reserves, dola_pool_id), EALREADY_EXIST_RESERVE);
        table::add(&mut storage.reserves, dola_pool_id, ReserveData {
            flag: true,
            last_update_timestamp: get_timestamp(oracle),
            treasury,
            treasury_factor,
            current_borrow_rate: 0,
            current_liquidity_rate: 0,
            current_borrow_index: RAY,
            current_liquidity_index: RAY,
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

    public fun get_user_collaterals(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
        let user_info = table::borrow(&mut storage.user_infos, dola_user_id);
        user_info.collaterals
    }

    public fun get_user_loans(storage: &mut Storage, dola_user_id: u64): vector<u16> {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
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

    public fun get_treasury_factor(
        storage: &mut Storage,
        dola_pool_id: u16)
    : u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).treasury_factor
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
    ): u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_liquidity_rate
    }

    public fun get_liquidity_index(
        storage: &mut Storage,
        dola_pool_id: u16): u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_liquidity_index
    }

    public fun get_borrow_rate(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_borrow_rate
    }

    public fun get_borrow_index(
        storage: &mut Storage,
        dola_pool_id: u16
    ): u64 {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, dola_pool_id).current_borrow_index
    }

    public fun get_borrow_rate_factors(
        storage: &mut Storage,
        dola_pool_id: u16
    ): (u64, u64, u64, u64) {
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
        assert!(current_amount >= scaled_amount, ENOT_ENOUGH_AMOUNT);
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
        assert!(current_amount >= scaled_amount, ENOT_ENOUGH_AMOUNT);
        table::add(&mut dtoken_scaled.user_state, dola_user_id, current_amount - scaled_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply - (scaled_amount as u128);
    }

    public fun add_user_collateral(
        _: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
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
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        if (!table::contains(&mut storage.user_infos, dola_user_id)) {
            table::add(&mut storage.user_infos, dola_user_id, UserInfo {
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
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let borrow_rate_factors = &mut table::borrow_mut(&mut storage.reserves, dola_pool_id).borrow_rate_factors;
        borrow_rate_factors.base_borrow_rate = base_borrow_rate;
        borrow_rate_factors.borrow_rate_slope1 = borrow_rate_slope1;
        borrow_rate_factors.borrow_rate_slope2 = borrow_rate_slope2;
        borrow_rate_factors.optimal_utilization = optimal_utilization;
    }

    public fun update_state(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_pool_id: u16,
        new_borrow_index: u64,
        new_liquidity_index: u64,
        mint_to_treasury_scaled: u64
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.current_borrow_index = new_borrow_index;
        reserve.current_liquidity_index = new_liquidity_index;

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
        new_borrow_rate: u64,
        new_liquidity_rate: u64,
    ) {
        assert!(table::contains(&storage.reserves, dola_pool_id), ENONEXISTENT_RESERVE);
        let reserve = table::borrow_mut(&mut storage.reserves, dola_pool_id);
        reserve.current_borrow_rate = new_borrow_rate;
        reserve.current_liquidity_rate = new_liquidity_rate;
    }
}
