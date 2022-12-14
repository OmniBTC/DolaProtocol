/// Manage the liquidity of all chains' pools
module pool_manager::pool_manager {
    use std::ascii::String;
    use std::hash;
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{DolaAddress, dola_chain_id};
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

    const ENONEXISTENT_CATALOG: u64 = 5;

    struct PoolManagerAdminCap has store, drop {
        pool_manager: address,
        count: u64
    }

    struct PoolManagerCap has store, drop {}

    struct PoolManagerInfo has key, store {
        id: UID,
        // dola_pool_id => AppInfo
        app_infos: Table<u16, AppInfo>,
        // dola_pool_id => PoolInfo
        pool_infos: Table<u16, PoolInfo>,
        // token and pool catalogs
        pool_catalog: PoolCatalog,
    }

    struct AppInfo has store {
        app_liquidity: Table<u16, u128>
    }

    struct PoolInfo has store {
        name: String,
        // token liquidity
        reserve: Liquidity,
        // pool address => PoolLiquidity
        pools: Table<DolaAddress, Liquidity>,
    }

    struct Liquidity has store {
        value: u64
    }

    struct PoolCatalog has store {
        pool_to_id: Table<DolaAddress, u16>,
        id_to_pools: Table<u16, vector<DolaAddress>>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolManagerInfo {
            id: object::new(ctx),
            app_infos: table::new(ctx),
            pool_infos: table::new(ctx),
            pool_catalog: PoolCatalog {
                pool_to_id: table::new(ctx),
                id_to_pools: table::new(ctx)
            }
        })
    }

    public fun get_pools_by_id(pool_manager: &mut PoolManagerInfo, dola_pool_id: u16): vector<DolaAddress> {
        let pool_catalog = &mut pool_manager.pool_catalog;
        assert!(table::contains(&mut pool_catalog.id_to_pools, dola_pool_id), ENONEXISTENT_CATALOG);
        *table::borrow(&mut pool_catalog.id_to_pools, dola_pool_id)
    }

    public fun get_id_by_pool(pool_manager: &mut PoolManagerInfo, pool: DolaAddress): u16 {
        let pool_catalog = &mut pool_manager.pool_catalog;
        assert!(table::contains(&mut pool_catalog.pool_to_id, pool), ENONEXISTENT_CATALOG);
        *table::borrow(&mut pool_catalog.pool_to_id, pool)
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
        dola_pool_id: u16,
        dst_chain: u16
    ): Option<DolaAddress> {
        let pools = get_pools_by_id(pool_manager_info, dola_pool_id);
        let len = vector::length(&pools);
        let i = 0;
        while (i < len) {
            let d = *vector::borrow(&pools, i);
            if (dola_chain_id(&d) == dst_chain) {
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
        dola_pool_name: String,
        dola_pool_id: u16,
        ctx: &mut TxContext
    ) {
        // register pool catalog
        let pool_catalog = &mut pool_manager_info.pool_catalog;
        if (!table::contains(&mut pool_catalog.id_to_pools, dola_pool_id)) {
            table::add(&mut pool_catalog.id_to_pools, dola_pool_id, vector::empty());
        };
        if (!table::contains(&mut pool_catalog.pool_to_id, pool)) {
            table::add(&mut pool_catalog.pool_to_id, pool, dola_pool_id);
            let pools = table::borrow_mut(&mut pool_catalog.id_to_pools, dola_pool_id);
            vector::push_back(pools, pool);
        };

        // register pool info
        let pool_infos = &mut pool_manager_info.pool_infos;
        if (table::contains(pool_infos, dola_pool_id)) {
            let pool_info = PoolInfo {
                name: dola_pool_name,
                reserve: zero_liquidity(),
                pools: table::new(ctx)
            };
            table::add(pool_infos, dola_pool_id, pool_info);
        };
        let pool_info = table::borrow_mut(pool_infos, dola_pool_id);
        table::add(&mut pool_info.pools, pool, zero_liquidity());
    }

    public fun zero_liquidity(): Liquidity {
        Liquidity {
            value: 0
        }
    }

    public fun get_app_liquidity_by_pool_id(
        pool_manager_info: &PoolManagerInfo,
        dola_pool_id: u16,
        app_id: u16
    ): u128 {
        let app_infos = &pool_manager_info.app_infos;

        assert!(table::contains(app_infos, dola_pool_id), ENONEXISTENT_RESERVE);
        let app_liquidity = &table::borrow(app_infos, dola_pool_id).app_liquidity;

        assert!(table::contains(app_liquidity, app_id), ENONEXISTENT_RESERVE);
        *table::borrow(app_liquidity, app_id)
    }


    public fun get_app_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        pool: DolaAddress,
        app_id: u16
    ): u128 {
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        get_app_liquidity_by_pool_id(pool_manager_info, dola_pool_id, app_id)
    }

    public fun token_liquidity(pool_manager_info: &mut PoolManagerInfo, pool: DolaAddress): u64 {
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        assert!(table::contains(&pool_manager_info.pool_infos, dola_pool_id), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow(&pool_manager_info.pool_infos, dola_pool_id);
        pool_info.reserve.value
    }

    public fun pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        pool: DolaAddress,
    ): u64 {
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        assert!(table::contains(&pool_manager_info.pool_infos, dola_pool_id), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow(&pool_manager_info.pool_infos, dola_pool_id);
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
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        let pool_infos = &mut pool_manager_info.pool_infos;
        let app_infos = &mut pool_manager_info.app_infos;

        if (!table::contains(app_infos, dola_pool_id)) {
            table::add(app_infos, dola_pool_id, AppInfo {
                app_liquidity: table::new(ctx)
            }) ;
        };
        let app_liquidity = &mut table::borrow_mut(app_infos, dola_pool_id).app_liquidity;
        let cur_app_liquidity;
        if (!table::contains(app_liquidity, app_id)) {
            cur_app_liquidity = 0;
        }else {
            cur_app_liquidity = table::remove(app_liquidity, app_id);
        };
        table::add(app_liquidity, app_id, cur_app_liquidity + (amount as u128));


        // update pool infos
        // update token liquidity
        assert!(table::contains(pool_infos, dola_pool_id), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow_mut(pool_infos, dola_pool_id);
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
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);

        let pool_infos = &mut pool_manager_info.pool_infos;

        let app_infos = &mut pool_manager_info.app_infos;

        assert!(table::contains(app_infos, dola_pool_id), ENONEXISTENT_RESERVE);
        let app_liquidity = &mut table::borrow_mut(app_infos, dola_pool_id).app_liquidity;
        let cur_app_liquidity = table::remove(app_liquidity, app_id);

        table::add(app_liquidity, app_id, cur_app_liquidity - (amount as u128));

        // update pool infos
        // update token liquidity
        assert!(table::contains(pool_infos, dola_pool_id), ENONEXISTENT_RESERVE);
        let pool_info = table::borrow_mut(pool_infos, dola_pool_id);
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
            let dola_pool_name = string(b"USDT");
            let pool = convert_external_address_to_dola(b"USDT");

            let cap = manager_cap_for_test();

            register_pool(&cap, &mut pool_manager_info, pool, dola_pool_name, 0, test_scenario::ctx(scenario));

            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_add_liquidity() {
        let manager = @pool_manager;
        let chainid = 0;
        let dola_pool_name = string(b"USDT");
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

            register_pool(&cap, &mut pool_manager_info, pool, dola_pool_name, 0, test_scenario::ctx(scenario));

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
        let dola_pool_name = string(b"USDT");
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

            register_pool(&cap, &mut pool_manager_info, pool, dola_pool_name, 0, test_scenario::ctx(scenario));

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
