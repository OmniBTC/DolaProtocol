/// Manage the liquidity of all chains' pools
module pool_manager::pool_manager {
    use std::ascii::String;
    use std::hash;
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{DolaAddress, dola_id, create_dola_address};
    use governance::governance::{Self, GovernanceExternalCap};
    use sui::bcs;
    use sui::object::{Self, UID, uid_to_address};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    #[test_only]
    use dola_types::types::convert_external_address_to_dola;
    #[test_only]
    use std::ascii::string;
    #[test_only]
    use sui::test_scenario;

    const EMUST_DEPLOYER: u64 = 0;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 1;

    const EONLY_ONE_ADMIN: u64 = 2;

    const EMUST_SOME: u64 = 3;

    const ENONEXISTENT_RESERVE: u64 = 4;


    struct PoolManagerAdminCap has store, drop {
        pool_manager: address,
        count: u64
    }


    struct TokenCategory has copy, drop, store {
        token_id: u16,
        token_name: String
    }

    struct PoolManagerCap has store, drop {}

    struct PoolManagerInfo has key, store {
        id: UID,
        // Mapping of pools of different chains to categories
        pool_to_catalog: Table<DolaAddress, String>,
        // Mapping of categories to different chain pools
        catalog_to_pool: Table<String, vector<DolaAddress>>,
        // catalog => AppInfo
        // todo! Will String cause the index to slow down, if it is replaced with a number later
        app_infos: Table<String, AppInfo>,
        // catalog => PoolInfo
        pool_infos: Table<String, PoolInfo>,
    }

    struct AppInfo has store {
        app_liquidity: Table<u16, u128>
    }

    struct PoolInfo has store {
        // token liquidity
        reserve: Liquidity,
        // chainid => PoolLiquidity
        pools: Table<DolaAddress, Liquidity>,
    }

    struct Liquidity has store {
        value: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolManagerInfo {
            id: object::new(ctx),
            pool_to_catalog: table::new(ctx),
            catalog_to_pool: table::new(ctx),
            app_infos: table::new(ctx),
            pool_infos: table::new(ctx)
        })
    }

    public entry fun register_admin_cap(pool_manager: &mut PoolManagerInfo, govern: &mut GovernanceExternalCap) {
        let admin = PoolManagerAdminCap { pool_manager: uid_to_address(&pool_manager.id), count: 0 };
        governance::add_external_cap(govern, hash::sha3_256(bcs::to_bytes(&admin)), admin);
    }

    public fun register_cap_with_admin(admin: &mut PoolManagerAdminCap): PoolManagerCap {
        admin.count = admin.count + 1;
        PoolManagerCap {}
    }

    public fun register_cap(admin: &mut Option<PoolManagerAdminCap>): PoolManagerCap {
        assert!(option::is_some(admin), EMUST_SOME);
        let admin = option::borrow_mut(admin);
        register_cap_with_admin(admin)
    }

    public fun find_pool_by_chain(
        pool_manager_info: &mut PoolManagerInfo,
        catalog: String,
        dst_chain: u16
    ): Option<DolaAddress> {
        assert!(table::contains(&pool_manager_info.catalog_to_pool, catalog), ENONEXISTENT_RESERVE);
        let catalog_to_pool = table::borrow(&mut pool_manager_info.catalog_to_pool, catalog);
        let len = vector::length(catalog_to_pool);
        let i = 0;
        while (i < len) {
            let d = *vector::borrow(catalog_to_pool, i);
            if (dola_id(&d) == dst_chain) {
                return option::some(d)
            };
            i = i + 1;
        };
        option::none()
    }

    public fun register_pool(
        _: &PoolManagerCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool: DolaAddress,
        catalog: String,
        ctx: &mut TxContext
    ) {
        let pool_info = PoolInfo {
            reserve: zero_liquidity(),
            pools: table::new(ctx)
        };
        table::add(&mut pool_manager_info.pool_to_catalog, pool, catalog);

        if (!table::contains(&pool_manager_info.catalog_to_pool, catalog)) {
            table::add(&mut pool_manager_info.catalog_to_pool, catalog, vector::empty());
        };
        let catalog_to_pool = table::borrow_mut(&mut pool_manager_info.catalog_to_pool, catalog);
        if (!vector::contains(catalog_to_pool, &pool)) {
            vector::push_back(catalog_to_pool, pool);
        };

        table::add(&mut pool_manager_info.pool_infos, catalog, pool_info);
    }

    public entry fun register_pool_admin(
        pool_manager_info: &mut PoolManagerInfo,
        dola_id: u16,
        dola_address: vector<u8>,
        catalog: String,
        ctx: &mut TxContext
    ) {
        let pool = create_dola_address(dola_id, dola_address);
        let pool_info = PoolInfo {
            reserve: zero_liquidity(),
            pools: table::new(ctx)
        };
        assert!(!table::contains(&pool_manager_info.pool_to_catalog, pool), ENONEXISTENT_RESERVE);
        table::add(&mut pool_manager_info.pool_to_catalog, pool, catalog);
        if (!table::contains(&pool_manager_info.catalog_to_pool, catalog)) {
            table::add(&mut pool_manager_info.catalog_to_pool, catalog, vector::empty());
        };
        let catalog_to_pool = table::borrow_mut(&mut pool_manager_info.catalog_to_pool, catalog);
        if (!vector::contains(catalog_to_pool, &pool)) {
            vector::push_back(catalog_to_pool, pool);
        };
        table::add(&mut pool_manager_info.pool_infos, catalog, pool_info);
    }

    public fun zero_liquidity(): Liquidity {
        Liquidity {
            value: 0
        }
    }

    public fun get_pool_catalog(pool_manager_info: &PoolManagerInfo, pool: DolaAddress): String {
        assert!(table::contains(&pool_manager_info.pool_to_catalog, pool), ENONEXISTENT_RESERVE);
        *table::borrow(&pool_manager_info.pool_to_catalog, pool)
    }

    public fun get_app_liquidity_by_catalog(
        pool_manager_info: &PoolManagerInfo,
        catalog: String,
        app_id: u16
    ): u128 {
        let app_infos = &pool_manager_info.app_infos;
        assert!(table::contains(app_infos, catalog), ENONEXISTENT_RESERVE);

        let app_liquidity = &table::borrow(app_infos, catalog).app_liquidity;
        assert!(table::contains(app_liquidity, app_id), ENONEXISTENT_RESERVE);
        *table::borrow(app_liquidity, app_id)
    }


    public fun get_app_liquidity(
        pool_manager_info: &PoolManagerInfo,
        pool: DolaAddress,
        app_id: u16
    ): u128 {
        let catalog = get_pool_catalog(pool_manager_info, pool);

        get_app_liquidity_by_catalog(pool_manager_info, catalog, app_id)
    }

    public fun token_liquidity(pool_manager_info: &mut PoolManagerInfo, pool: DolaAddress): u64 {
        let catalog = get_pool_catalog(pool_manager_info, pool);
        assert!(table::contains(&pool_manager_info.pool_infos, catalog), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow(&pool_manager_info.pool_infos, catalog);
        pool_info.reserve.value
    }

    public fun pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        pool: DolaAddress,
    ): u64 {
        let catalog = get_pool_catalog(pool_manager_info, pool);
        assert!(table::contains(&pool_manager_info.pool_infos, catalog), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow(&pool_manager_info.pool_infos, catalog);
        assert!(table::contains(&pool_info.pools, pool), ENONEXISTENT_RESERVE);
        let pool_liquidity = table::borrow(&pool_info.pools, pool);
        pool_liquidity.value
    }

    public fun add_liquidity(
        _: &PoolManagerCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool: DolaAddress,
        app_id: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let catalog = get_pool_catalog(pool_manager_info, pool);
        let pool_infos = &mut pool_manager_info.pool_infos;
        let app_infos = &mut pool_manager_info.app_infos;

        if (!table::contains(app_infos, catalog)) {
            table::add(app_infos, catalog, AppInfo {
                app_liquidity: table::new(ctx)
            }) ;
        };
        let app_liquidity = &mut table::borrow_mut(app_infos, catalog).app_liquidity;
        let cur_app_liquidity;
        if (!table::contains(app_liquidity, app_id)) {
            cur_app_liquidity = 0;
        }else {
            cur_app_liquidity = table::remove(app_liquidity, app_id);
        };
        table::add(app_liquidity, app_id, cur_app_liquidity + (amount as u128));


        // update pool infos
        // update token liquidity
        if (!table::contains(pool_infos, catalog)) {
            let pool_info = PoolInfo {
                reserve: zero_liquidity(),
                pools: table::new(ctx)
            };
            table::add(pool_infos, catalog, pool_info);
        };
        let pool_info = table::borrow_mut(pool_infos, catalog);
        pool_info.reserve.value = pool_info.reserve.value + amount;

        // update pool liquidity
        let pools_liquidity = &mut pool_info.pools;
        if (!table::contains(pools_liquidity, pool)) {
            table::add(pools_liquidity, pool, zero_liquidity());
        };
        let liquidity = table::borrow_mut(pools_liquidity, pool);
        liquidity.value = liquidity.value + amount;
    }

    public fun remove_liquidity(
        _: &PoolManagerCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool: DolaAddress,
        app_id: u16,
        amount: u64,
    )
    {
        let catalog = get_pool_catalog(pool_manager_info, pool);

        let pool_infos = &mut pool_manager_info.pool_infos;

        let app_infos = &mut pool_manager_info.app_infos;

        assert!(table::contains(app_infos, catalog), ENONEXISTENT_RESERVE);
        let app_liquidity = &mut table::borrow_mut(app_infos, catalog).app_liquidity;
        let cur_app_liquidity = table::remove(app_liquidity, app_id);

        table::add(app_liquidity, app_id, cur_app_liquidity - (amount as u128));

        // update pool infos
        // update token liquidity
        assert!(table::contains(pool_infos, catalog), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow_mut(pool_infos, catalog);
        assert!(pool_info.reserve.value >= amount, ENOT_ENOUGH_LIQUIDITY);
        pool_info.reserve.value = pool_info.reserve.value - amount;

        // update pool liquidity
        let pools_liquidity = &mut pool_info.pools;
        assert!(table::contains(pools_liquidity, pool), ENONEXISTENT_RESERVE);
        let liquidity = table::borrow_mut(pools_liquidity, pool);
        liquidity.value = liquidity.value - amount;
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun manager_cap_for_test(): PoolManagerCap {
        PoolManagerCap {}
    }

    #[test]
    public fun test_register_pool() {
        let manager = @pool_manager;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let catalog = string(b"USDT");
            let pool = convert_external_address_to_dola(b"USDT");

            let cap = manager_cap_for_test();

            register_pool(&cap, &mut pool_manager_info, pool, catalog, test_scenario::ctx(scenario));

            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_add_liquidity() {
        let manager = @pool_manager;
        let chainid = 0;
        let catalog = string(b"USDT");
        let pool = convert_external_address_to_dola(b"USDT");
        let amount = 100;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);

            let cap = manager_cap_for_test();

            register_pool(&cap, &mut pool_manager_info, pool, catalog, test_scenario::ctx(scenario));

            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let cap = manager_cap_for_test();
            assert!(token_liquidity(&mut pool_manager_info, pool) == 0, 0);
            add_liquidity(
                &cap,
                &mut pool_manager_info,
                pool,
                0,
                amount,
                test_scenario::ctx(scenario)
            );

            assert!(token_liquidity(&mut pool_manager_info, pool) == amount, 0);
            assert!(pool_liquidity(&mut pool_manager_info, pool) == amount, 0);

            test_scenario::return_shared(pool_manager_info);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_remove_liquidity() {
        let manager = @pool_manager;
        let chainid = 0;
        let catalog = string(b"USDT");
        let pool = convert_external_address_to_dola(b"USDT");
        let amount = 100;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);

            let cap = manager_cap_for_test();

            register_pool(&cap, &mut pool_manager_info, pool, catalog, test_scenario::ctx(scenario));

            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let cap = manager_cap_for_test();
            add_liquidity(
                &cap,
                &mut pool_manager_info,
                pool,
                0,
                amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let cap = manager_cap_for_test();

            assert!(token_liquidity(&mut pool_manager_info, pool) == amount, 0);
            assert!(pool_liquidity(&mut pool_manager_info, pool) == amount, 0);

            remove_liquidity(
                &cap,
                &mut pool_manager_info,
                pool,
                0,
                amount
            );

            assert!(token_liquidity(&mut pool_manager_info, pool) == 0, 0);
            assert!(pool_liquidity(&mut pool_manager_info, pool) == 0, 0);

            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::end(scenario_val);
    }
}
