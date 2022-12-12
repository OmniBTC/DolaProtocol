module omnipool::pool {
    use std::vector;

    use serde::serde::{serialize_vector, serialize_u64, deserialize_u64, vector_slice, serialize_u16, deserialize_u16};
    use aptos_framework::coin::{Coin, is_account_registered};
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::coin;
    use std::hash::sha3_256;
    use aptos_std::type_info;
    use std::string;
    use serde::u16;
    use serde::u16::U16;
    use std::bcs;
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::util::address_from_bytes;

    const SEED: vector<u8> = b"Dola omnipool";

    const EINVALID_LENGTH: u64 = 0;

    const EMUST_DEPLOYER: u64 = 1;

    const EINVALID_TOKEN: u64 = 2;

    const EINVALID_ADMIN: u64 = 3;

    const EMUST_INIT: u64 = 4;

    const ENOT_INIT: u64 = 5;

    const EHAS_POOL: u64 = 6;


    struct PoolManager has key {
        resource_cap: SignerCapability
    }

    /// The user's information is recorded in the protocol, and the pool only needs to record itself
    struct Pool<phantom CoinType> has key, store {
        balance: Coin<CoinType>
    }

    /// Give permission to the bridge when Pool is in use
    struct PoolCap has key, store {}

    struct DolaAddress has copy, drop, store {
        addr: vector<u8>
    }

    public fun convert_address_to_dola(addr: address): DolaAddress {
        DolaAddress { addr: bcs::to_bytes(&addr) }
    }

    public fun convert_vector_to_dola(addr: vector<u8>): DolaAddress {
        DolaAddress { addr }
    }

    public fun convert_dola_to_address(addr: DolaAddress): address {
        address_from_bytes(addr.addr)
    }

    public fun convert_dola_to_vector(addr: DolaAddress): vector<u8> {
        addr.addr
    }

    /// Make sure the user has aptos coin, and help register if they don't.
    fun transfer<X>(coin_x: Coin<X>, to: address) {
        if (!is_account_registered<X>(to) && type_info::type_of<X>() == type_info::type_of<AptosCoin>()) {
            aptos_account::create_account(to);
        };
        coin::deposit(to, coin_x);
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @omnipool
    }

    public fun ensure_init(): bool {
        exists<PoolManager>(get_resource_address())
    }

    public fun exist_pool<CoinType>(): bool {
        exists<Pool<CoinType>>(get_resource_address())
    }

    public fun register_cap(sender: &signer): PoolCap {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        // todo! consider into govern
        PoolCap {}
    }

    public fun delete_cap(pool_cap: PoolCap) {
        let PoolCap {} = pool_cap;
    }

    public entry fun init_pool(sender: &signer) {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        assert!(!ensure_init(), ENOT_INIT);
        let (resource_signer, resource_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, PoolManager {
            resource_cap
        });
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@omnipool, SEED)
    }

    public fun get_coin_decimal<CoinType>(): u8 {
        coin::decimals<CoinType>()
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
    public fun normal_amount<CoinType>(amount: u64): u64 {
        let cur_decimal = get_coin_decimal<CoinType>();
        let target_decimal = 8;
        convert_amount(amount, cur_decimal, target_decimal)
    }

    public fun unnormal_amount<CoinType>(amount: u64): u64 {
        let cur_decimal = 8;
        let target_decimal = get_coin_decimal<CoinType>();
        convert_amount(amount, cur_decimal, target_decimal)
    }

    public entry fun create_pool<CoinType>(sender: &signer) acquires PoolManager {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        assert!(ensure_init(), EMUST_INIT);
        assert!(!exist_pool<CoinType>(), EHAS_POOL);
        let resource_cap = &borrow_global<PoolManager>(get_resource_address()).resource_cap;
        move_to(&account::create_signer_with_capability(resource_cap), Pool<CoinType> {
            balance: coin::zero()
        });
    }

    /// call by user or application
    public fun deposit_to<CoinType>(
        sender: &signer,
        deposit_coin: Coin<CoinType>,
        app_id: U16,
        app_payload: vector<u8>,
    ): vector<u8> acquires Pool {
        let amount = normal_amount<CoinType>(coin::value(&deposit_coin));
        let user = convert_address_to_dola(signer::address_of(sender));
        let token_name = *string::bytes(&type_info::type_name<CoinType>());
        let pool_address = vector_slice(&sha3_256(token_name), 0, 40);
        let pool_payload = encode_send_deposit_payload(
            pool_address,
            user,
            amount,
            token_name,
            app_id,
            app_payload
        );
        let pool = borrow_global_mut<Pool<CoinType>>(get_resource_address());
        coin::merge(&mut pool.balance, deposit_coin);
        pool_payload
    }

    /// call by user or application
    public fun withdraw_to<CoinType>(
        sender: &signer,
        app_id: U16,
        app_payload: vector<u8>,
    ): vector<u8> {
        let user = convert_address_to_dola(signer::address_of(sender));
        let token_name = *string::bytes(&type_info::type_name<CoinType>());
        let pool_address = vector_slice(&sha3_256(token_name), 0, 40);
        let pool_payload = encode_send_withdraw_payload(
            pool_address,
            user,
            token_name,
            app_id,
            app_payload
        );
        pool_payload
    }

    /// call by bridge
    public fun inner_withdraw<CoinType>(
        _: &PoolCap,
        user: DolaAddress,
        amount: u64,
        token_name: vector<u8>,
    ) acquires Pool {
        let user = convert_dola_to_address(user);
        amount = unnormal_amount<CoinType>(amount);
        let pool = borrow_global_mut<Pool<CoinType>>(get_resource_address());
        let balance = coin::extract(&mut pool.balance, amount);
        assert!(token_name == *string::bytes(&type_info::type_name<CoinType>()), EINVALID_TOKEN);
        transfer(balance, user);
    }

    // todo! Should this action be moved to the application level or delete
    public fun deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        sender: &signer,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_user: DolaAddress,
        app_id: U16,
        app_payload: vector<u8>,
    ): vector<u8> acquires Pool {
        let amount = normal_amount<DepositCoinType>(coin::value(&deposit_coin));
        let depoist_user = convert_address_to_dola(signer::address_of(sender));
        let deposit_token_name = *string::bytes(&type_info::type_name<DepositCoinType>());
        let deposit_pool_address = vector_slice(&sha3_256(deposit_token_name), 0, 40);

        let pool = borrow_global_mut<Pool<DepositCoinType>>(get_resource_address());
        coin::merge(&mut pool.balance, deposit_coin);

        let withdraw_token_name = *string::bytes(&type_info::type_name<WithdrawCoinType>());
        let withdraw_pool_address = vector_slice(&sha3_256(withdraw_token_name), 0, 40);
        let pool_payload = encode_send_deposit_and_withdraw_payload(
            deposit_pool_address,
            depoist_user,
            amount,
            deposit_token_name,
            withdraw_pool_address,
            withdraw_user,
            withdraw_token_name,
            app_id,
            app_payload
        );
        pool_payload
    }


    /// encode deposit msg
    public fun encode_send_deposit_payload(
        pool: vector<u8>,
        user: DolaAddress,
        amount: u64,
        token_name: vector<u8>,
        app_id: U16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&pool)));
        serialize_vector(&mut pool_payload, pool);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&user.addr)));
        serialize_vector(&mut pool_payload, user.addr);
        serialize_u64(&mut pool_payload, amount);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&token_name)));
        serialize_vector(&mut pool_payload, token_name);
        serialize_u16(&mut pool_payload, app_id);
        if (vector::length(&app_payload) > 0) {
            serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&app_payload)));
            serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode deposit msg
    public fun decode_send_deposit_payload(
        pool_payload: vector<u8>
    ): (vector<u8>, DolaAddress, u64, vector<u8>, U16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_address_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = pool_address_len;
        let pool_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let user_address_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = user_address_len;
        let user_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let token_name_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = token_name_len ;
        let token_name = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
            index = index + data_len;

            data_len = app_payload_len ;
            app_payload = vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (pool_address, convert_vector_to_dola(user_address), amount, token_name, app_id, app_payload)
    }

    /// encode whihdraw msg
    public fun encode_send_withdraw_payload(
        pool: vector<u8>,
        user: DolaAddress,
        token_name: vector<u8>,
        app_id: U16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&pool)));
        serialize_vector(&mut pool_payload, pool);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&user.addr)));
        serialize_vector(&mut pool_payload, user.addr);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&token_name)));
        serialize_vector(&mut pool_payload, token_name);
        serialize_u16(&mut pool_payload, app_id);
        if (vector::length(&app_payload) > 0) {
            serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&app_payload)));
            serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode withdraw msg
    public fun decode_send_withdraw_payload(
        pool_payload: vector<u8>
    ): (vector<u8>, DolaAddress, vector<u8>, U16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_address_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = pool_address_len;
        let pool_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let user_address_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = user_address_len;
        let user_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let token_name_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = token_name_len ;
        let token_name = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
            index = index + data_len;

            data_len = app_payload_len ;
            app_payload = vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (pool_address, convert_vector_to_dola(user_address), token_name, app_id, app_payload)
    }

    public fun encode_send_deposit_and_withdraw_payload(
        deposit_pool: vector<u8>,
        deposit_user: DolaAddress,
        deposit_amount: u64,
        deposit_token: vector<u8>,
        withdraw_pool: vector<u8>,
        withdraw_user: DolaAddress,
        withdraw_token: vector<u8>,
        app_id: U16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&deposit_pool)));
        serialize_vector(&mut pool_payload, deposit_pool);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&deposit_user.addr)));
        serialize_vector(&mut pool_payload, deposit_user.addr);
        serialize_u64(&mut pool_payload, deposit_amount);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&deposit_token)));
        serialize_vector(&mut pool_payload, deposit_token);

        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&withdraw_pool)));
        serialize_vector(&mut pool_payload, withdraw_pool);

        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&withdraw_user.addr)));
        serialize_vector(&mut pool_payload, withdraw_user.addr);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&withdraw_token)));
        serialize_vector(&mut pool_payload, withdraw_token);

        serialize_u16(&mut pool_payload, app_id);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&app_payload)));
        serialize_vector(&mut pool_payload, app_payload);
        pool_payload
    }

    public fun decode_send_deposit_and_withdraw_payload(
        pool_payload: vector<u8>
    ): (vector<u8>, DolaAddress, u64, vector<u8>, vector<u8>, DolaAddress, vector<u8>, U16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let deposit_pool_address_len = u16::to_u64(
            deserialize_u16(&vector_slice(&pool_payload, index, index + data_len))
        );
        index = index + data_len;

        data_len = deposit_pool_address_len;
        let deposit_pool_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let deposit_user_address_len = u16::to_u64(
            deserialize_u16(&vector_slice(&pool_payload, index, index + data_len))
        );
        index = index + data_len;

        data_len = deposit_user_address_len;
        let deposit_user_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 8;
        let deposit_amount = deserialize_u64(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let deposit_token_name_len = u16::to_u64(
            deserialize_u16(&vector_slice(&pool_payload, index, index + data_len))
        );
        index = index + data_len;

        data_len = deposit_token_name_len;
        let deposit_token_name = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let withdraw_pool_address_len = u16::to_u64(
            deserialize_u16(&vector_slice(&pool_payload, index, index + data_len))
        );
        index = index + data_len;

        data_len = withdraw_pool_address_len;
        let withdraw_pool_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let withdraw_user_address_len = u16::to_u64(
            deserialize_u16(&vector_slice(&pool_payload, index, index + data_len))
        );
        index = index + data_len;

        data_len = withdraw_user_address_len;
        let withdraw_user_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let withdraw_token_name_len = u16::to_u64(
            deserialize_u16(&vector_slice(&pool_payload, index, index + data_len))
        );
        index = index + data_len;

        data_len = withdraw_token_name_len;
        let withdraw_token_name = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
            index = index + data_len;

            data_len = app_payload_len ;
            app_payload = vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (deposit_pool_address, convert_vector_to_dola(
            deposit_user_address
        ), deposit_amount, deposit_token_name, withdraw_pool_address, convert_vector_to_dola(
            withdraw_user_address
        ), withdraw_token_name, app_id, app_payload)
    }

    /// encode deposit msg
    public fun encode_receive_withdraw_payload(
        pool: vector<u8>,
        user: DolaAddress,
        amount: u64,
        token_name: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&pool)));
        serialize_vector(&mut pool_payload, pool);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&user.addr)));
        serialize_vector(&mut pool_payload, user.addr);
        serialize_u64(&mut pool_payload, amount);
        serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&token_name)));
        serialize_vector(&mut pool_payload, token_name);
        pool_payload
    }

    /// decode deposit msg
    public fun decode_receive_withdraw_payload(pool_payload: vector<u8>): (vector<u8>, DolaAddress, u64, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_address_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = pool_address_len;
        let pool_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let user_address_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = user_address_len;
        let user_address = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let token_name_len = u16::to_u64(deserialize_u16(&vector_slice(&pool_payload, index, index + data_len)));
        index = index + data_len;

        data_len = token_name_len;
        let token_name = vector_slice(&pool_payload, index, index + data_len);
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);

        (pool_address, convert_vector_to_dola(user_address), amount, token_name)
    }
}
