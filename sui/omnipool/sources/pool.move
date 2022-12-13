module omnipool::pool {
    use std::ascii;
    use std::type_name;
    use std::vector;

    use serde::serde::{serialize_vector, serialize_u64, deserialize_u64, vector_slice, serialize_u16, deserialize_u16};
    use sui::balance::{Self, Balance, zero};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, address_from_bytes};
    use sui::transfer::{Self, share_object};
    use sui::tx_context::{Self, TxContext};

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;
    use std::bcs;

    const EINVALID_LENGTH: u64 = 0;

    const EMUST_DEPLOYER: u64 = 1;

    const EINVALID_TOKEN: u64 = 2;

    const DOLAID: u16 = 0;

    /// The user's information is recorded in the protocol, and the pool only needs to record itself
    struct Pool<phantom CoinType> has key, store {
        id: UID,
        balance: Balance<CoinType>,
        decimal: u8
    }

    /// Give permission to the bridge when Pool is in use
    struct PoolCap has key, store {
        id: UID
    }

    /// Used to represent user address and pool address
    struct DolaAddress has copy, drop, store {
        dola_id: u16,
        dola_address: vector<u8>
    }

    public fun convert_address_to_dola(addr: address): DolaAddress {
        DolaAddress {
            dola_id: DOLAID,
            dola_address: bcs::to_bytes(&addr)
        }
    }

    public fun convert_dola_to_address(addr: DolaAddress): address {
        address_from_bytes(addr.dola_address)
    }

    public fun convert_pool_to_dola<CoinType>(): DolaAddress {
        let dola_address = ascii::into_bytes(type_name::into_string(type_name::get<CoinType>()));
        DolaAddress {
            dola_id: DOLAID,
            dola_address
        }
    }

    public fun convert_dola_to_pool(addr: DolaAddress): vector<u8> {
        addr.dola_address
    }

    public fun convert_external_address_to_dola(addr: vector<u8>): DolaAddress {
        DolaAddress {
            dola_id: DOLAID,
            dola_address: addr
        }
    }

    public fun convert_dola_to_external_address(addr: DolaAddress): vector<u8> {
        addr.dola_address
    }

    public fun unpack_dola(addr: DolaAddress): (u16, vector<u8>) {
        let DolaAddress { dola_id, dola_address } = addr;
        (dola_id, dola_address)
    }

    public fun pack_dola(dola_id: u16, dola_address: vector<u8>): DolaAddress {
        DolaAddress { dola_id, dola_address }
    }


    public fun encode_dola_address(addr: DolaAddress): vector<u8> {
        let data = vector::empty();
        serialize_u16(&mut data, addr.dola_id);
        serialize_vector(&mut data, addr.dola_address);
        data
    }

    public fun decode_dola_address(addr: vector<u8>): DolaAddress {
        let len = vector::length(&addr);
        let index = 0;
        let data_len;

        data_len = 2;
        let dola_id = deserialize_u16(&vector_slice(&addr, index, index + data_len));
        index = index + data_len;

        let dola_address = vector_slice(&addr, index, len);
        DolaAddress {
            dola_id,
            dola_address
        }
    }


    public fun register_cap(ctx: &mut TxContext): PoolCap {
        // todo! consider into govern
        PoolCap {
            id: object::new(ctx)
        }
    }

    public fun delete_cap(pool_cap: PoolCap) {
        let PoolCap { id } = pool_cap;
        object::delete(id);
    }

    /// todo! Realize cross create pool
    public entry fun create_pool<CoinType>(decimal: u8, ctx: &mut TxContext) {
        share_object(Pool<CoinType> {
            id: object::new(ctx),
            balance: zero<CoinType>(),
            decimal
        })
    }

    public fun get_coin_decimal<CoinType>(pool: &Pool<CoinType>): u8 {
        pool.decimal
    }

    public fun convert_amount(amount: u64, cur_decimal: u8, target_decimal: u8): u64 {
        while (cur_decimal != target_decimal) {
            if (cur_decimal < target_decimal) {
                amount = amount * 10;
                cur_decimal = cur_decimal + 1;
            }else {
                amount = amount / 10;
                cur_decimal = cur_decimal - 1;
            };
        };
        amount
    }

    /// Normal amount in dola protocol
    /// 1. Pool class normal
    /// 2. Application class normal
    public fun normal_amount<CoinType>(pool: &Pool<CoinType>, amount: u64): u64 {
        let cur_decimal = get_coin_decimal<CoinType>(pool);
        let target_decimal = 8;
        convert_amount(amount, cur_decimal, target_decimal)
    }

    public fun unnormal_amount<CoinType>(pool: &Pool<CoinType>, amount: u64): u64 {
        let cur_decimal = 8;
        let target_decimal = get_coin_decimal<CoinType>(pool);
        convert_amount(amount, cur_decimal, target_decimal)
    }

    /// call by user or application
    public fun deposit_to<CoinType>(
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let amount = normal_amount(pool, coin::value(&deposit_coin));
        let user_addr = convert_address_to_dola(tx_context::sender(ctx));
        let pool_addr = convert_pool_to_dola<CoinType>();
        let pool_payload = encode_send_deposit_payload(pool_addr, user_addr, amount, app_id, app_payload);
        balance::join(&mut pool.balance, coin::into_balance(deposit_coin));
        pool_payload
    }

    /// call by user or application
    public fun withdraw_to<CoinType>(
        _pool: &mut Pool<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let user_addr = convert_address_to_dola(tx_context::sender(ctx));
        let pool_addr = convert_pool_to_dola<CoinType>();
        let pool_payload = encode_send_withdraw_payload(pool_addr, user_addr, app_id, app_payload);
        pool_payload
    }

    /// call by bridge
    public fun inner_withdraw<CoinType>(
        _: &PoolCap,
        pool: &mut Pool<CoinType>,
        user: DolaAddress,
        amount: u64,
        pool_addr: DolaAddress,
        ctx: &mut TxContext
    ) {
        let user = convert_dola_to_address(user);
        amount = unnormal_amount(pool, amount);
        let balance = balance::split(&mut pool.balance, amount);
        let coin = coin::from_balance(balance, ctx);
        assert!(
            pool_addr.dola_address == ascii::into_bytes(type_name::into_string(type_name::get<CoinType>())),
            EINVALID_TOKEN
        );
        transfer::transfer(coin, user);
    }

    public fun deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        deposit_pool: &mut Pool<DepositCoinType>,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_user: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let amount = normal_amount(deposit_pool, coin::value(&deposit_coin));
        let depoist_user = convert_address_to_dola(tx_context::sender(ctx));
        let deposit_pool_address = convert_pool_to_dola<DepositCoinType>();

        balance::join(&mut deposit_pool.balance, coin::into_balance(deposit_coin));
        let withdraw_pool_address = convert_pool_to_dola<WithdrawCoinType>();

        let pool_payload = encode_send_deposit_and_withdraw_payload(
            deposit_pool_address,
            depoist_user,
            amount,
            withdraw_pool_address,
            withdraw_user,
            app_id,
            app_payload
        );
        pool_payload
    }

    /// encode deposit msg
    public fun encode_send_deposit_payload(
        pool: DolaAddress,
        user: DolaAddress,
        amount: u64,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool = encode_dola_address(pool);
        serialize_u16(&mut pool_payload, (vector::length(&pool) as u16));
        serialize_vector(&mut pool_payload, pool);

        let user = encode_dola_address(user);
        serialize_u16(&mut pool_payload, (vector::length(&user) as u16));
        serialize_vector(&mut pool_payload, user);

        serialize_u64(&mut pool_payload, amount);

        serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode deposit msg
    public fun decode_send_deposit_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (pool, user, amount, app_id, app_payload)
    }

    /// encode whihdraw msg
    public fun encode_send_withdraw_payload(
        pool: DolaAddress,
        user: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool = encode_dola_address(pool);
        serialize_u16(&mut pool_payload, (vector::length(&pool) as u16));
        serialize_vector(&mut pool_payload, pool);

        let user = encode_dola_address(user);
        serialize_u16(&mut pool_payload, (vector::length(&user) as u16));
        serialize_vector(&mut pool_payload, user);

        serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode withdraw msg
    public fun decode_send_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (pool, user, app_id, app_payload)
    }

    public fun encode_send_deposit_and_withdraw_payload(
        deposit_pool: DolaAddress,
        deposit_user: DolaAddress,
        deposit_amount: u64,
        withdraw_pool: DolaAddress,
        withdraw_user: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let deposit_pool = encode_dola_address(deposit_pool);
        serialize_u16(&mut pool_payload, (vector::length(&deposit_pool) as u16));
        serialize_vector(&mut pool_payload, deposit_pool);

        let deposit_user = encode_dola_address(deposit_user);
        serialize_u16(&mut pool_payload, (vector::length(&deposit_user) as u16));
        serialize_vector(&mut pool_payload, deposit_user);

        serialize_u64(&mut pool_payload, deposit_amount);

        let withdraw_pool = encode_dola_address(withdraw_pool);
        serialize_u16(&mut pool_payload, (vector::length(&withdraw_pool) as u16));
        serialize_vector(&mut pool_payload, withdraw_pool);

        let withdraw_user = encode_dola_address(withdraw_user);
        serialize_u16(&mut pool_payload, (vector::length(&withdraw_user) as u16));
        serialize_vector(&mut pool_payload, withdraw_user);

        serialize_u16(&mut pool_payload, app_id);

        serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
        serialize_vector(&mut pool_payload, app_payload);

        pool_payload
    }

    public fun decode_send_deposit_and_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, DolaAddress, DolaAddress, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let deposit_pool_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (deposit_pool_len as u64);
        let deposit_pool = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let deposit_user_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (deposit_user_len as u64);
        let deposit_user = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let deposit_amount = deserialize_u64(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let withdraw_pool_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (withdraw_pool_len as u64);
        let withdraw_pool = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let withdraw_user_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (withdraw_user_len as u64);
        let withdraw_user = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (deposit_pool, deposit_user, deposit_amount, withdraw_pool, withdraw_user, app_id, app_payload)
    }

    /// encode deposit msg
    public fun encode_receive_withdraw_payload(
        pool: DolaAddress,
        user: DolaAddress,
        amount: u64
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool = encode_dola_address(pool);
        serialize_u16(&mut pool_payload, (vector::length(&pool) as u16));
        serialize_vector(&mut pool_payload, pool);

        serialize_u16(&mut pool_payload, (vector::length(&user.dola_address) as u16));
        serialize_vector(&mut pool_payload, user.dola_address);

        serialize_u64(&mut pool_payload, amount);

        pool_payload
    }

    /// decode deposit msg
    public fun decode_receive_withdraw_payload(pool_payload: vector<u8>): (DolaAddress, DolaAddress, u64) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user = decode_dola_address(vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);

        (pool, user, amount)
    }

    #[test]
    public fun test_deposit_to() {
        let manager = @0xA;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            create_pool<SUI>(9, ctx);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(scenario);
            assert!(balance::value(&pool.balance) == 0, 0);
            let ctx = test_scenario::ctx(scenario);
            let coin = coin::mint_for_testing<SUI>(100, ctx);
            let app_payload = vector::empty<u8>();
            deposit_to<SUI>(&mut pool, coin, 0, app_payload, ctx);
            assert!(balance::value(&pool.balance) == 100, 0);
            test_scenario::return_shared(pool);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_withdraw_to() {
        let manager = @0x0;
        let user = @0xC;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            create_pool<SUI>(9, ctx);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(scenario);
            let manager_cap = register_cap(test_scenario::ctx(scenario));
            let ctx = test_scenario::ctx(scenario);
            let pool_addr = convert_pool_to_dola<SUI>();

            let balance = balance::create_for_testing<SUI>(100);

            balance::join(&mut pool.balance, balance);

            assert!(balance::value(&pool.balance) == 100, 0);

            inner_withdraw<SUI>(&manager_cap, &mut pool, convert_address_to_dola(user), 10, pool_addr, ctx);

            assert!(balance::value(&pool.balance) == 0, 0);

            test_scenario::return_shared(pool);
            delete_cap(manager_cap);
        };
        test_scenario::end(scenario_val);
    }
}
