/// Manage the liquidity of all chains' pools
module omnicore::poolmanager {
    use serde::u16::{Self, U16};
    use serde::u256::{Self, U256};
    use sui::dynamic_object_field;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    friend omnicore::messagecore;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 1;

    struct PoolManagerCap has key, store {
        id: UID
    }

    struct PoolInfo has store, copy, drop {
        chainid: U16,
        pool: vector<u8>,
    }

    struct LiquidityInfo has key, store {
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

    public fun remove_liquidity(cap: &mut PoolManagerCap,
                                chainid: u64,
                                pool_address: vector<u8>,
                                user_address: vector<u8>,
                                amount: u64) {
        let pool_info = create_pool_info(chainid, pool_address);
        let liquidity_info = dynamic_object_field::borrow_mut<PoolInfo, LiquidityInfo>(&mut cap.id, pool_info);
        liquidity_info.reserve = liquidity_info.reserve - amount;
        let user_info = table::borrow(&mut liquidity_info.users, user_address);
        assert!(u256::compare(&user_info.liduitidy, &u256::from_u64(amount)) == 1, ENOT_ENOUGH_LIQUIDITY);
        let new_liquidity = u256::sub(user_info.liduitidy, u256::from_u64(amount));
        let user_info = table::borrow_mut(&mut liquidity_info.users, user_address);
        user_info.liduitidy = new_liquidity;
    }

    public fun register_pool(
        cap: &mut PoolManagerCap,
        chainid: u64,
        pool_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let pool_info = create_pool_info(chainid, pool_address);
        let liquidity_info = LiquidityInfo {
            reserve: 0,
            users: table::new(ctx)
        };
        dynamic_object_field::add(&mut cap.id, pool_info, liquidity_info)
    }
}