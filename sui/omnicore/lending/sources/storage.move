module lending::storage {
    use std::hash;

    use governance::governance::{Self, GovernanceExternalCap};
    use sui::bcs;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{TxContext, epoch};
    use sui::types;

    const EONLY_ONE_ADMIN: u64 = 0;

    const EALREADY_EXIST_RESERVE: u64 = 1;

    const ENONEXISTENT_RESERVE: u64 = 2;

    struct Storage has key {
        id: UID,
        // token name -> reserve data
        reserves: Table<vector<u8>, ReserveData>
    }

    struct ReserveData has store {
        // Teserve flag
        // todo! add some flags
        flag: bool,
        // Timestamp of last update
        // todo: use timestamp after sui implementation, now use epoch
        last_update_timestamp: u64,
        // Treasury
        treasury: address,
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
        // user address => scale balance
        user_state: Table<vector<u8>, u64>,
        // total supply of scale balance
        total_supply: u128,
    }

    struct BorrowRateFactors has store {
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64
    }

    struct StorageAdminCap has store, drop {
        count: u64
    }

    struct StorageCap has store, drop {}

    public entry fun register_admin_cap(govern: &mut GovernanceExternalCap) {
        let admin = StorageAdminCap { count: 0 };
        assert!(types::is_one_time_witness<StorageAdminCap>(&admin), EONLY_ONE_ADMIN);
        governance::add_external_cap(govern, hash::sha3_256(bcs::to_bytes(&admin)), admin);
    }

    public entry fun register_cap_with_admin(admin: &mut StorageAdminCap): StorageCap {
        admin.count = admin.count + 1;
        StorageCap {}
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            reserves: table::new(ctx),
        });
    }

    public entry fun register_new_reserve(
        _: &mut StorageAdminCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        treasury: address,
        treasury_factor: u64,
        collateral_coefficient: u64,
        borrow_coefficient: u64,
        ctx: &mut TxContext
    ) {
        assert!(!table::contains(&storage.reserves, token_name), EALREADY_EXIST_RESERVE);
        table::add(&mut storage.reserves, token_name, ReserveData {
            flag: true,
            last_update_timestamp: epoch(ctx),
            treasury,
            treasury_factor,
            current_borrow_rate: 0,
            current_liquidity_rate: 0,
            current_borrow_index: 0,
            current_liquidity_index: 0,
            collateral_coefficient,
            borrow_coefficient,
            borrow_rate_factors: BorrowRateFactors {
                base_borrow_rate: 0,
                borrow_rate_slope1: 0,
                borrow_rate_slope2: 0,
                optimal_utilization: 0
            },
            otoken_scaled: ScaledBalance {
                user_state: table::new<vector<u8>, u64>(ctx),
                total_supply: 0,
            },
            dtoken_scaled: ScaledBalance {
                user_state: table::new<vector<u8>, u64>(ctx),
                total_supply: 0,
            },
        });
    }

    public fun get_treasury_factor(
        storage: &mut Storage,
        token_name: vector<u8>)
    : u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).treasury_factor
    }

    public fun get_last_update_timestamp(
        storage: &mut Storage,
        token_name: vector<u8>
    ): u64 {
        // todo! too much judge contains
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).last_update_timestamp
    }

    public fun get_otoken_scaled_total_supply(
        storage: &mut Storage,
        token_name: vector<u8>
    ): u128 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).otoken_scaled.total_supply
    }

    public fun get_dtoken_scaled_total_supply(
        storage: &mut Storage,
        token_name: vector<u8>
    ): u128 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).dtoken_scaled.total_supply
    }

    public fun get_liquidity_rate(
        storage: &mut Storage,
        token_name: vector<u8>
    ): u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).current_liquidity_rate
    }

    public fun get_liquidity_index(
        storage: &mut Storage,
        token_name: vector<u8>): u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).current_liquidity_index
    }

    public fun get_borrow_rate(
        storage: &mut Storage,
        token_name: vector<u8>
    ): u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).current_borrow_rate
    }

    public fun get_borrow_index(
        storage: &mut Storage,
        token_name: vector<u8>)
    : u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        table::borrow(&storage.reserves, token_name).current_borrow_index
    }

    public fun get_borrow_rate_factors(
        storage: &mut Storage,
        token_name: vector<u8>
    ): (u64, u64, u64, u64) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let borrow_rate_factors = &table::borrow(&storage.reserves, token_name).borrow_rate_factors;
        (borrow_rate_factors.base_borrow_rate, borrow_rate_factors.borrow_rate_slope1, borrow_rate_factors.borrow_rate_slope2, borrow_rate_factors.optimal_utilization)
    }

    public fun mint_otoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        user: vector<u8>,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let otoken_scaled = &mut table::borrow_mut(&mut storage.reserves, token_name).otoken_scaled;
        let current_amount;

        if (table::contains(&otoken_scaled.user_state, user)) {
            current_amount = table::remove(&mut otoken_scaled.user_state, user);
        }else {
            current_amount = 0
        };
        table::add(&mut otoken_scaled.user_state, user, scaled_amount + current_amount);
        otoken_scaled.total_supply = otoken_scaled.total_supply + (scaled_amount as u128);
    }

    public fun burn_otoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        user: vector<u8>,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let otoken_scaled = &mut table::borrow_mut(&mut storage.reserves, token_name).otoken_scaled;
        let current_amount;

        if (table::contains(&otoken_scaled.user_state, user)) {
            current_amount = table::remove(&mut otoken_scaled.user_state, user);
        } else {
            current_amount = 0
        };
        table::add(&mut otoken_scaled.user_state, user, scaled_amount - current_amount);
        otoken_scaled.total_supply = otoken_scaled.total_supply - (scaled_amount as u128);
    }

    public fun mint_dtoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        user: vector<u8>,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let dtoken_scaled = &mut table::borrow_mut(&mut storage.reserves, token_name).dtoken_scaled;
        let current_amount;

        if (table::contains(&dtoken_scaled.user_state, user)) {
            current_amount = table::remove(&mut dtoken_scaled.user_state, user);
        }else {
            current_amount = 0
        };
        table::add(&mut dtoken_scaled.user_state, user, scaled_amount + current_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply + (scaled_amount as u128);
    }

    public fun burn_dtoken_scaled(
        _: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        user: vector<u8>,
        scaled_amount: u64
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let dtoken_scaled = &mut table::borrow_mut(&mut storage.reserves, token_name).dtoken_scaled;
        let current_amount;

        if (table::contains(&dtoken_scaled.user_state, user)) {
            current_amount = table::remove(&mut dtoken_scaled.user_state, user);
        } else {
            current_amount = 0
        };
        table::add(&mut dtoken_scaled.user_state, user, scaled_amount - current_amount);
        dtoken_scaled.total_supply = dtoken_scaled.total_supply - (scaled_amount as u128);
    }

    public fun update_borrow_rate_factors(
        _: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let borrow_rate_factors = &mut table::borrow_mut(&mut storage.reserves, token_name).borrow_rate_factors;
        borrow_rate_factors.base_borrow_rate = base_borrow_rate;
        borrow_rate_factors.borrow_rate_slope1 = borrow_rate_slope1;
        borrow_rate_factors.borrow_rate_slope2 = borrow_rate_slope2;
        borrow_rate_factors.optimal_utilization = optimal_utilization;
    }

    public fun update_state(
        cap: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        new_borrow_index: u64,
        new_liquidity_index: u64,
        mint_to_treasury_scaled: u64
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let reserve = table::borrow_mut(&mut storage.reserves, token_name);
        reserve.current_borrow_index = new_borrow_index;
        reserve.current_liquidity_index = new_liquidity_index;

        // Mint to treasury
        let user = bcs::to_bytes(&table::borrow(&storage.reserves, token_name).treasury);
        mint_otoken_scaled(
            cap,
            storage,
            token_name,
            user,
            mint_to_treasury_scaled
        );
    }

    public fun update_interest_rate(
        _: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
        new_borrow_rate: u64,
        new_liquidity_rate: u64,
    ) {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let reserve = table::borrow_mut(&mut storage.reserves, token_name);
        reserve.current_borrow_rate = new_borrow_rate;
        reserve.current_liquidity_rate = new_liquidity_rate;
    }
}
