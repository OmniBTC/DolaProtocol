/// Manage the liquidity of all chains' pools
module pool_manager::pool_manager {
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    #[test_only]
    use sui::bcs::to_bytes;
    #[test_only]
    use sui::test_scenario;

    const EMUST_DEPLOYER: u64 = 0;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 1;

    struct PoolManagerCap has key, store {
        id: UID
    }

    struct PoolManagerInfo has key, store {
        id: UID,
        // token_name => PoolInfo
        pool_infos: Table<vector<u8>, PoolInfo>,
        // user_address => UserLiquidity
        user_infos: Table<vector<u8>, UserLiquidity>
    }

    struct PoolInfo has store {
        // token liquidity
        reserve: Liquidity,
        // chainid => PoolLiquidity
        pools: Table<u64, PoolLiquidity>,
    }

    struct PoolLiquidity has store {
        // address => Liquidity
        liquidity: Table<vector<u8>, Liquidity>
    }

    struct UserLiquidity has store {
        // token_name => Liquidity
        liquidity: Table<vector<u8>, Liquidity>,
    }

    struct Liquidity has store {
        value: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolManagerInfo {
            id: object::new(ctx),
            pool_infos: table::new(ctx),
            user_infos: table::new(ctx)
        })
    }

    public entry fun register_cap(ctx: &mut TxContext): PoolManagerCap {
        assert!(tx_context::sender(ctx) == @pool_manager, EMUST_DEPLOYER);
        PoolManagerCap {
            id: object::new(ctx)
        }
    }

    public fun register_pool(
        _: &PoolManagerCap,
        pool_manager_info: &mut PoolManagerInfo,
        token_name: vector<u8>,
        ctx: &mut TxContext
    ) {
        let pool_info = PoolInfo {
            reserve: zero_liquidity(),
            pools: table::new(ctx)
        };
        table::add(&mut pool_manager_info.pool_infos, token_name, pool_info);
    }

    public fun zero_liquidity(): Liquidity {
        Liquidity {
            value: 0
        }
    }

    public fun user_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        token_name: vector<u8>,
        user_address: vector<u8>
    ): u64 {
        let user_infos = &mut pool_manager_info.user_infos;
        let user_liquidity = table::borrow(user_infos, user_address);
        let liquidity = table::borrow(&user_liquidity.liquidity, token_name);
        liquidity.value
    }

    public fun token_liquidity(pool_manager_info: &mut PoolManagerInfo, token_name: vector<u8>): u64 {
        let pool_info = table::borrow(&pool_manager_info.pool_infos, token_name);
        pool_info.reserve.value
    }

    public fun pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        token_name: vector<u8>,
        chainid: u64,
        pool_address: vector<u8>
    ): u64 {
        let pool_info = table::borrow(&pool_manager_info.pool_infos, token_name);
        let pool_liquidity = table::borrow(&pool_info.pools, chainid);
        let liquidity = table::borrow(&pool_liquidity.liquidity, pool_address);
        liquidity.value
    }

    public fun add_liquidity(
        _: &PoolManagerCap,
        pool_manager_info: &mut PoolManagerInfo,
        token_name: vector<u8>,
        chainid: u64,
        pool_address: vector<u8>,
        user_address: vector<u8>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let pool_infos = &mut pool_manager_info.pool_infos;
        let user_infos = &mut pool_manager_info.user_infos;

        // update pool infos
        // update token liquidity
        if (!table::contains(pool_infos, token_name)) {
            let pool_info = PoolInfo {
                reserve: zero_liquidity(),
                pools: table::new(ctx)
            };
            table::add(pool_infos, token_name, pool_info);
        };
        let pool_info = table::borrow_mut(pool_infos, token_name);
        pool_info.reserve.value = pool_info.reserve.value + amount;

        // update pool liquidity
        let pools_liquidity = &mut pool_info.pools;

        if (!table::contains(pools_liquidity, chainid)) {
            let pool_liquidity = PoolLiquidity {
                liquidity: table::new(ctx)
            };
            table::add(pools_liquidity, chainid, pool_liquidity);
        };
        let pool_liquidity = table::borrow_mut(pools_liquidity, chainid);
        if (!table::contains(&mut pool_liquidity.liquidity, pool_address)) {
            table::add(&mut pool_liquidity.liquidity, pool_address, zero_liquidity());
        };

        let liquidity = table::borrow_mut(&mut pool_liquidity.liquidity, pool_address);
        liquidity.value = liquidity.value + amount;

        // update user infos
        if (!table::contains(user_infos, user_address)) {
            let user_liquidity = UserLiquidity {
                liquidity: table::new(ctx)
            };
            table::add(user_infos, user_address, user_liquidity);
        };
        let user_liquidity = table::borrow_mut(user_infos, user_address);
        if (!table::contains(&mut user_liquidity.liquidity, token_name)) {
            table::add(&mut user_liquidity.liquidity, token_name, zero_liquidity());
        };
        let liquidity = table::borrow_mut(&mut user_liquidity.liquidity, token_name);
        liquidity.value = liquidity.value + amount;
    }

    public fun remove_liquidity(
        _: &PoolManagerCap,
        pool_manager_info: &mut PoolManagerInfo,
        token_name: vector<u8>,
        chainid: u64,
        pool_address: vector<u8>,
        user_address: vector<u8>,
        amount: u64,
    )
    {
        let pool_infos = &mut pool_manager_info.pool_infos;
        let user_infos = &mut pool_manager_info.user_infos;

        // update pool infos
        // update token liquidity
        let pool_info = table::borrow_mut(pool_infos, token_name);
        assert!(pool_info.reserve.value >= amount, ENOT_ENOUGH_LIQUIDITY);
        pool_info.reserve.value = pool_info.reserve.value - amount;

        // update pool liquidity
        let pools_liquidity = &mut pool_info.pools;
        let pool_liquidity = table::borrow_mut(pools_liquidity, chainid);

        let liquidity = table::borrow_mut(&mut pool_liquidity.liquidity, pool_address);
        liquidity.value = liquidity.value - amount;

        // update user infos
        let user_liquidity = table::borrow_mut(user_infos, user_address);
        let liquidity = table::borrow_mut(&mut user_liquidity.liquidity, token_name);
        liquidity.value = liquidity.value - amount;
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
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
            let token_name = b"USDT";

            let cap = register_cap(test_scenario::ctx(scenario));

            register_pool(&cap, &mut pool_manager_info, token_name, test_scenario::ctx(scenario));

            transfer::transfer(cap, manager);
            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_add_liquidity() {
        let manager = @pool_manager;
        let chainid = 1;
        let token_name = b"USDT";
        let pool_address = @0xB;
        let user_address = @0xC;
        let amount = 100;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);

            let cap = register_cap(test_scenario::ctx(scenario));

            register_pool(&cap, &mut pool_manager_info, token_name, test_scenario::ctx(scenario));

            transfer::transfer(cap, manager);
            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);
            assert!(token_liquidity(&mut pool_manager_info, token_name) == 0, 0);
            add_liquidity(
                &cap,
                &mut pool_manager_info,
                token_name,
                chainid,
                to_bytes(&pool_address),
                to_bytes(&user_address),
                amount,
                test_scenario::ctx(scenario)
            );

            assert!(token_liquidity(&mut pool_manager_info, token_name) == amount, 0);
            assert!(pool_liquidity(&mut pool_manager_info, token_name, chainid, to_bytes(&pool_address)) == amount, 0);
            assert!(user_liquidity(&mut pool_manager_info, token_name, to_bytes(&user_address)) == amount, 0);

            test_scenario::return_to_sender(scenario, cap);
            test_scenario::return_shared(pool_manager_info);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_remove_liquidity() {
        let manager = @pool_manager;
        let chainid = 1;
        let token_name = b"USDT";
        let pool_address = @0xB;
        let user_address = @0xC;
        let amount = 100;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);

            let cap = register_cap(test_scenario::ctx(scenario));

            register_pool(&cap, &mut pool_manager_info, token_name, test_scenario::ctx(scenario));

            transfer::transfer(cap, manager);
            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);
            // assert!(token_liquidity(&mut pool_manager_info, pool_name) == 0, 0);
            add_liquidity(
                &cap,
                &mut pool_manager_info,
                token_name,
                chainid,
                to_bytes(&pool_address),
                to_bytes(&user_address),
                amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, cap);
            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool_manager_info = test_scenario::take_shared<PoolManagerInfo>(scenario);
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);

            assert!(token_liquidity(&mut pool_manager_info, token_name) == amount, 0);
            assert!(pool_liquidity(&mut pool_manager_info, token_name, chainid, to_bytes(&pool_address)) == amount, 0);
            assert!(user_liquidity(&mut pool_manager_info, token_name, to_bytes(&user_address)) == amount, 0);

            remove_liquidity(
                &cap,
                &mut pool_manager_info,
                token_name,
                chainid,
                to_bytes(&pool_address),
                to_bytes(&user_address),
                amount
            );

            assert!(token_liquidity(&mut pool_manager_info, token_name) == 0, 0);
            assert!(pool_liquidity(&mut pool_manager_info, token_name, chainid, to_bytes(&pool_address)) == 0, 0);
            assert!(user_liquidity(&mut pool_manager_info, token_name, to_bytes(&user_address)) == 0, 0);

            test_scenario::return_to_sender(scenario, cap);
            test_scenario::return_shared(pool_manager_info);
        };
        test_scenario::end(scenario_val);
    }
}
