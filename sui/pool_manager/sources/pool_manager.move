/// Manage the liquidity of all chains' pools
module pool_manager::pool_manager {
    use serde::u16::{Self, U16};
    use serde::u256::{Self, U256};
    use sui::dynamic_object_field;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    #[test_only]
    use sui::bcs::to_bytes;
    #[test_only]
    use sui::test_scenario;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 1;

    struct PoolManagerCap has key, store {
        id: UID
    }

    struct PoolInfo has store, copy, drop {
        chainid: U16,
        pool: vector<u8>,
    }

    struct LiquidityInfo has key, store {
        id: UID,
        reserve: u64,
        users: Table<vector<u8>, UserInfo>
    }

    struct UserInfo has store, copy, drop {
        liduitidy: U256
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(PoolManagerCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx))
    }

    fun create_pool_info(chianid: u64, pool: vector<u8>): PoolInfo {
        PoolInfo {
            chainid: u16::from_u64(chianid),
            pool
        }
    }

    public fun register_pool(
        cap: &mut PoolManagerCap,
        chainid: u64,
        pool_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let pool_info = create_pool_info(chainid, pool_address);
        let liquidity_info = LiquidityInfo {
            id: object::new(ctx),
            reserve: 0,
            users: table::new(ctx)
        };
        dynamic_object_field::add(&mut cap.id, pool_info, liquidity_info)
    }

    public fun add_liquidity(
        cap: &mut PoolManagerCap,
        chainid: u64,
        pool_address: vector<u8>,
        user_address: vector<u8>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let pool_info = create_pool_info(chainid, pool_address);
        if (!dynamic_object_field::exists_(&mut cap.id, pool_info)) {
            register_pool(cap, chainid, pool_address, ctx);
        };
        let liquidity_info = dynamic_object_field::borrow_mut<PoolInfo, LiquidityInfo>(&mut cap.id, pool_info);

        liquidity_info.reserve = liquidity_info.reserve + amount;

        if (!table::contains(&mut liquidity_info.users, user_address)) {
            table::add(&mut liquidity_info.users, user_address, UserInfo {
                liduitidy: u256::zero()
            });
        };

        let user_info = table::borrow(&mut liquidity_info.users, user_address);
        let new_liquidity = u256::add(user_info.liduitidy, u256::from_u64(amount));
        let user_info = table::borrow_mut(&mut liquidity_info.users, user_address);
        user_info.liduitidy = new_liquidity;
    }

    public fun remove_liquidity(
        cap: &mut PoolManagerCap,
        chainid: u64,
        pool_address: vector<u8>,
        user_address: vector<u8>,
        amount: u64)
    {
        let pool_info = create_pool_info(chainid, pool_address);
        let liquidity_info = dynamic_object_field::borrow_mut<PoolInfo, LiquidityInfo>(&mut cap.id, pool_info);

        assert!(liquidity_info.reserve >= amount, ENOT_ENOUGH_LIQUIDITY);

        liquidity_info.reserve = liquidity_info.reserve - amount;

        let user_info = table::borrow(&mut liquidity_info.users, user_address);
        let new_liquidity = u256::sub(user_info.liduitidy, u256::from_u64(amount));
        let user_info = table::borrow_mut(&mut liquidity_info.users, user_address);
        user_info.liduitidy = new_liquidity;
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test]
    public fun test_register_pool() {
        let manager = @0xA;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);
            let chainid = 1;
            let pool_address = @0xB;

            let pool_info = create_pool_info(chainid, to_bytes(&pool_address));
            assert!(!dynamic_object_field::exists_(&mut cap.id, pool_info), 0);

            register_pool(&mut cap, chainid, to_bytes(&pool_address), test_scenario::ctx(scenario));

            assert!(dynamic_object_field::exists_(&mut cap.id, pool_info), 0);
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_add_liquidity() {
        let manager = @0xA;
        let chainid = 1;
        let pool_address = @0xB;
        let user_address = @0xC;
        let amount = 100;
        let pool_info = create_pool_info(chainid, to_bytes(&pool_address));

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);
            register_pool(&mut cap, chainid, to_bytes(&pool_address), test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);

            add_liquidity(
                &mut cap,
                chainid,
                to_bytes(&pool_address),
                to_bytes(&user_address),
                amount,
                test_scenario::ctx(scenario)
            );
            let liquidity_info = dynamic_object_field::borrow<PoolInfo, LiquidityInfo>(&cap.id, pool_info);
            let user_info = table::borrow(&liquidity_info.users, to_bytes(&user_address));
            assert!(liquidity_info.reserve == amount, 0);
            assert!(user_info.liduitidy == u256::from_u64(amount), 0);
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_remove_liquidity() {
        let manager = @0xA;
        let chainid = 1;
        let pool_address = @0xB;
        let user_address = @0xC;
        let amount = 100;
        let pool_info = create_pool_info(chainid, to_bytes(&pool_address));

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, manager);
        {
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);
            register_pool(&mut cap, chainid, to_bytes(&pool_address), test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);

            add_liquidity(
                &mut cap,
                chainid,
                to_bytes(&pool_address),
                to_bytes(&user_address),
                amount,
                test_scenario::ctx(scenario)
            );
            let liquidity_info = dynamic_object_field::borrow<PoolInfo, LiquidityInfo>(&cap.id, pool_info);
            let user_info = table::borrow(&liquidity_info.users, to_bytes(&user_address));
            assert!(liquidity_info.reserve == amount, 0);
            assert!(user_info.liduitidy == u256::from_u64(amount), 0);
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let cap = test_scenario::take_from_sender<PoolManagerCap>(scenario);

            remove_liquidity(
                &mut cap,
                chainid,
                to_bytes(&pool_address),
                to_bytes(&user_address),
                amount
            );
            let liquidity_info = dynamic_object_field::borrow<PoolInfo, LiquidityInfo>(&cap.id, pool_info);
            let user_info = table::borrow(&liquidity_info.users, to_bytes(&user_address));
            assert!(liquidity_info.reserve == 0, 0);
            assert!(user_info.liduitidy == u256::from_u64(0), 0);
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::end(scenario_val);
    }
}
