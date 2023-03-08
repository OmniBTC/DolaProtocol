module omnipool::pool {
    use std::signer;
    use std::string;
    use std::vector;

    use aptos_std::type_info;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    use dola_types::types::{Self, DolaAddress};
    use serde::serde;

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

    /// The user_addr's information is recorded in the protocol, and the pool only needs to record itself
    struct Pool<phantom CoinType> has key, store {
        balance: Coin<CoinType>
    }

    /// Give permission to the bridge when Pool is in use
    struct PoolCap has key, store {}

    /// Make sure the user_addr has aptos coin, and help register if they don't.
    fun transfer<X>(coin_x: Coin<X>, to: address) {
        if (!coin::is_account_registered<X>(to) && type_info::type_of<X>() == type_info::type_of<AptosCoin>()) {
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

    /// call by user_addr or application
    public fun deposit_to<CoinType>(
        sender: &signer,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
    ): vector<u8> acquires Pool {
        let amount = normal_amount<CoinType>(coin::value(&deposit_coin));
        let user_addr = types::convert_address_to_dola(signer::address_of(sender));
        let pool_addr = types::convert_pool_to_dola<CoinType>();
        let pool_payload = encode_send_deposit_payload(
            pool_addr, user_addr, amount, app_id, app_payload
        );
        let pool = borrow_global_mut<Pool<CoinType>>(get_resource_address());
        coin::merge(&mut pool.balance, deposit_coin);
        pool_payload
    }

    /// call by user_addr or application
    public fun withdraw_to(
        sender: &signer,
        withdraw_chain_id: u16,
        withdraw_pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
    ): vector<u8> {
        let user_addr = types::convert_address_to_dola(signer::address_of(sender));
        let pool_addr = types::create_dola_address(withdraw_chain_id, withdraw_pool_address);
        let pool_payload = encode_send_withdraw_payload(pool_addr, user_addr, app_id, app_payload);
        pool_payload
    }

    /// call by bridge
    public fun inner_withdraw<CoinType>(
        _: &PoolCap,
        user_addr: DolaAddress,
        amount: u64,
        pool_addr: DolaAddress,
    ) acquires Pool {
        let user_addr = types::convert_dola_to_address(user_addr);
        amount = unnormal_amount<CoinType>(amount);
        let pool = borrow_global_mut<Pool<CoinType>>(get_resource_address());
        let balance = coin::extract(&mut pool.balance, amount);
        assert!(
            types::get_dola_address(&pool_addr) == *string::bytes(&type_info::type_name<CoinType>()),
            EINVALID_TOKEN
        );
        transfer(balance, user_addr);
    }

    // todo! Should this action be moved to the application level or delete
    public fun deposit_and_withdraw<DepositCoinType>(
        sender: &signer,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_chain_id: u16,
        withdraw_pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
    ): vector<u8> acquires Pool {
        let amount = normal_amount<DepositCoinType>(coin::value(&deposit_coin));
        let depoist_user = types::convert_address_to_dola(signer::address_of(sender));
        let deposit_pool_address = types::convert_pool_to_dola<DepositCoinType>();

        let pool = borrow_global_mut<Pool<DepositCoinType>>(get_resource_address());
        coin::merge(&mut pool.balance, deposit_coin);
        let withdraw_pool_address = types::create_dola_address(withdraw_chain_id, withdraw_pool_address);

        let pool_payload = encode_send_deposit_and_withdraw_payload(
            deposit_pool_address,
            depoist_user,
            amount,
            withdraw_pool_address,
            app_id,
            app_payload
        );
        pool_payload
    }


    /// encode deposit msg
    public fun encode_send_deposit_payload(
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        amount: u64,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_addr) as u16));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_addr) as u16));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u64(&mut pool_payload, amount);

        serde::serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serde::serialize_vector(&mut pool_payload, app_payload);
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
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = serde::vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (pool_addr, user_addr, amount, app_id, app_payload)
    }

    /// encode whihdraw msg
    public fun encode_send_withdraw_payload(
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_addr) as u16));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_addr) as u16));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serde::serialize_vector(&mut pool_payload, app_payload);
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
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = serde::vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (pool_addr, user_addr, app_id, app_payload)
    }

    public fun encode_send_deposit_and_withdraw_payload(
        deposit_pool: DolaAddress,
        deposit_user: DolaAddress,
        deposit_amount: u64,
        withdraw_pool: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let deposit_pool = types::encode_dola_address(deposit_pool);
        serde::serialize_u16(&mut pool_payload, (vector::length(&deposit_pool) as u16));
        serde::serialize_vector(&mut pool_payload, deposit_pool);

        let deposit_user = types::encode_dola_address(deposit_user);
        serde::serialize_u16(&mut pool_payload, (vector::length(&deposit_user) as u16));
        serde::serialize_vector(&mut pool_payload, deposit_user);

        serde::serialize_u64(&mut pool_payload, deposit_amount);

        let withdraw_pool = types::encode_dola_address(withdraw_pool);
        serde::serialize_u16(&mut pool_payload, (vector::length(&withdraw_pool) as u16));
        serde::serialize_vector(&mut pool_payload, withdraw_pool);

        serde::serialize_u16(&mut pool_payload, app_id);

        serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
        serde::serialize_vector(&mut pool_payload, app_payload);

        pool_payload
    }

    public fun decode_send_deposit_and_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, DolaAddress, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let deposit_pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = (deposit_pool_len as u64);
        let deposit_pool = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let deposit_user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (deposit_user_len as u64);
        let deposit_user = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let deposit_amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let withdraw_pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (withdraw_pool_len as u64);
        let withdraw_pool = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_payload_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = (app_payload_len as u64);
            app_payload = serde::vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (deposit_pool, deposit_user, deposit_amount, withdraw_pool, app_id, app_payload)
    }

    /// encode deposit msg
    public fun encode_receive_withdraw_payload(
        source_chain_id: u16,
        nonce: u64,
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        amount: u64
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        // encode nonce
        serde::serialize_u16(&mut pool_payload, source_chain_id);
        serde::serialize_u64(&mut pool_payload, nonce);

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_addr) as u16));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_addr) as u16));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u64(&mut pool_payload, amount);

        pool_payload
    }

    /// decode withdraw msg
    public fun decode_receive_withdraw_payload(pool_payload: vector<u8>): (u16, u64, DolaAddress, DolaAddress, u64) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let source_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);

        (source_chain_id, nonce, pool_addr, user_addr, amount)
    }

    #[test]
    public fun test_encode_decode() {
        let pool = @0x11;
        let user = @0x22;
        let amount = 100;
        let app_id = 0;
        let app_payload = vector::empty<u8>();
        // test encode and decode send_deposit_payload
        let send_deposit_payload = encode_send_deposit_payload(
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            amount,
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_amount, decoded_app_id, decoded_app_payload) = decode_send_deposit_payload(
            send_deposit_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode send_withdraw_payload
        let send_withdraw_payload = encode_send_withdraw_payload(
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_app_id, decoded_app_payload) = decode_send_withdraw_payload(
            send_withdraw_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode send_deposit_and_withdraw_payload
        let withdraw_pool = @0x33;
        let send_deposit_and_withdraw_payload = encode_send_deposit_and_withdraw_payload(
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            amount,
            types::convert_address_to_dola(withdraw_pool),
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_amount, decoded_withdraw_pool, decoded_app_id, decoded_app_payload) = decode_send_deposit_and_withdraw_payload(
            send_deposit_and_withdraw_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
        assert!(types::convert_dola_to_address(decoded_withdraw_pool) == withdraw_pool, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode receive_withdraw_payload
        let receive_withdraw_payload = encode_receive_withdraw_payload(
            0,
            0,
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            amount
        );
        let (source_chain_id, nonce, decoded_pool, decoded_user, decoded_amount) = decode_receive_withdraw_payload(
            receive_withdraw_payload
        );
        assert!(source_chain_id == 0, 0);
        assert!(nonce == 0, 0);
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
    }
}
