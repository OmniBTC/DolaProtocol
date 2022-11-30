module lending::storage {
    use std::hash;
    use std::option::{Self, Option};
    use std::vector;

    use app_manager::app_manager::{Self, AppCap};
    use governance::governance::{Self, GovernanceExternalCap};
    use sui::bcs;
    use sui::object::{Self, UID, uid_to_address};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{TxContext, epoch};

    const EONLY_ONE_ADMIN: u64 = 0;

    const EALREADY_EXIST_RESERVE: u64 = 1;

    const ENONEXISTENT_RESERVE: u64 = 2;

    const ENONEXISTENT_USERINFO: u64 = 3;

    const EHAS_NOT_OTOKEN: u64 = 4;

    const EHAS_NOT_DTOKEN: u64 = 5;

    const EMUST_NONE: u64 = 6;

    const EMUST_SOME: u64 = 7;

    struct Storage has key {
        id: UID,
        app_cap: Option<AppCap>,
        // token name -> reserve data
        reserves: Table<vector<u8>, ReserveData>,
        // users address -> user info
        user_infos: Table<vector<u8>, UserInfo>
    }

    struct UserInfo has store {
        // token names
        collaterals: vector<vector<u8>>,
        // token names
        loans: vector<vector<u8>>
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
        storage: address,
        count: u64
    }

    struct StorageCap has store, drop {}

    public entry fun register_admin_cap(storage: &mut Storage, govern: &mut GovernanceExternalCap) {
        let admin = StorageAdminCap { storage: uid_to_address(&storage.id), count: 0 };
        governance::add_external_cap(govern, hash::sha3_256(bcs::to_bytes(&admin)), admin);
    }

    public fun register_cap_with_admin(admin: &mut StorageAdminCap): StorageCap {
        admin.count = admin.count + 1;
        StorageCap {}
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            app_cap: option::none(),
            reserves: table::new(ctx),
            user_infos: table::new(ctx)
        });
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

    public fun get_user_collaterals(storage: &mut Storage, user_address: vector<u8>): vector<vector<u8>> {
        let user_info = table::borrow(&mut storage.user_infos, user_address);
        user_info.collaterals
    }

    public fun get_user_loans(storage: &mut Storage, user_address: vector<u8>): vector<vector<u8>> {
        let user_info = table::borrow(&mut storage.user_infos, user_address);
        user_info.loans
    }

    public fun get_user_scaled_otoken(
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ): u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let reserve = table::borrow(&storage.reserves, token_name);
        assert!(table::contains(&reserve.otoken_scaled.user_state, user_address), EHAS_NOT_OTOKEN);
        *table::borrow(&reserve.otoken_scaled.user_state, user_address)
    }

    public fun get_user_scaled_dtoken(
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ): u64 {
        assert!(table::contains(&storage.reserves, token_name), ENONEXISTENT_RESERVE);
        let reserve = table::borrow(&storage.reserves, token_name);
        assert!(table::contains(&reserve.dtoken_scaled.user_state, user_address), EHAS_NOT_DTOKEN);
        *table::borrow(&reserve.dtoken_scaled.user_state, user_address)
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
        token_name: vector<u8>
    ): u64 {
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

    public fun add_user_collateral(
        _: &StorageCap,
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ) {
        if (!table::contains(&mut storage.user_infos, user_address)) {
            table::add(&mut storage.user_infos, user_address, UserInfo {
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
        let user_info = table::borrow_mut(&mut storage.user_infos, user_address);
        if (!vector::contains(&user_info.collaterals, &token_name)) {
            vector::push_back(&mut user_info.collaterals, token_name)
        }
    }

    public fun remove_user_collateral(
        _: &StorageCap,
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ) {
        assert!(table::contains(&mut storage.user_infos, user_address), ENONEXISTENT_USERINFO);
        let user_info = table::borrow_mut(&mut storage.user_infos, user_address);

        let (exist, index) = vector::index_of(&user_info.collaterals, &token_name);
        if (exist) {
            let _ = vector::remove(&mut user_info.collaterals, index);
        }
    }

    public fun add_user_loan(
        _: &StorageCap,
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ) {
        if (!table::contains(&mut storage.user_infos, user_address)) {
            table::add(&mut storage.user_infos, user_address, UserInfo {
                collaterals: vector::empty(),
                loans: vector::empty()
            });
        };
        let user_info = table::borrow_mut(&mut storage.user_infos, user_address);
        if (!vector::contains(&user_info.loans, &token_name)) {
            vector::push_back(&mut user_info.loans, token_name)
        }
    }

    public fun remove_user_loan(
        _: &StorageCap,
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ) {
        assert!(table::contains(&mut storage.user_infos, user_address), ENONEXISTENT_USERINFO);
        let user_info = table::borrow_mut(&mut storage.user_infos, user_address);

        let (exist, index) = vector::index_of(&user_info.loans, &token_name);
        if (exist) {
            let _ = vector::remove(&mut user_info.loans, index);
        }
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
