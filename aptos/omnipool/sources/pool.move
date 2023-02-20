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
    use serde::u16::{Self, U16};

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
        app_id: U16,
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
    public fun withdraw_to<CoinType>(
        sender: &signer,
        app_id: U16,
        app_payload: vector<u8>,
    ): vector<u8> {
        let user_addr = types::convert_address_to_dola(signer::address_of(sender));
        let pool_addr = types::convert_pool_to_dola<CoinType>();
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
        assert!(types::get_dola_address(&pool_addr) == *string::bytes(&type_info::type_name<CoinType>()), EINVALID_TOKEN);
        transfer(balance, user_addr);
    }

    // todo! Should this action be moved to the application level or delete
    public fun deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        sender: &signer,
        deposit_coin: Coin<DepositCoinType>,
        app_id: U16,
        app_payload: vector<u8>,
    ): vector<u8> acquires Pool {
        let amount = normal_amount<DepositCoinType>(coin::value(&deposit_coin));
        let depoist_user = types::convert_address_to_dola(signer::address_of(sender));
        let deposit_pool_address = types::convert_pool_to_dola<DepositCoinType>();

        let pool = borrow_global_mut<Pool<DepositCoinType>>(get_resource_address());
        coin::merge(&mut pool.balance, deposit_coin);
        let withdraw_pool_address = types::convert_pool_to_dola<WithdrawCoinType>();

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
        app_id: U16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&pool_addr)));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&user_addr)));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u64(&mut pool_payload, amount);

        serde::serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&app_payload)));
            serde::serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode deposit msg
    public fun decode_send_deposit_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, U16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(pool_len);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
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

            data_len = u16::to_u64(app_payload_len);
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
        app_id: U16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&pool_addr)));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&user_addr)));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&app_payload)));
            serde::serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode withdraw msg
    public fun decode_send_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, U16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(pool_len);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
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

            data_len = u16::to_u64(app_payload_len);
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
        app_id: U16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let deposit_pool = types::encode_dola_address(deposit_pool);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&deposit_pool)));
        serde::serialize_vector(&mut pool_payload, deposit_pool);

        let deposit_user = types::encode_dola_address(deposit_user);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&deposit_user)));
        serde::serialize_vector(&mut pool_payload, deposit_user);

        serde::serialize_u64(&mut pool_payload, deposit_amount);

        let withdraw_pool = types::encode_dola_address(withdraw_pool);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&withdraw_pool)));
        serde::serialize_vector(&mut pool_payload, withdraw_pool);

        serde::serialize_u16(&mut pool_payload, app_id);

        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&app_payload)));
        serde::serialize_vector(&mut pool_payload, app_payload);

        pool_payload
    }

    public fun decode_send_deposit_and_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, DolaAddress, U16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let deposit_pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(deposit_pool_len);
        let deposit_pool = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let deposit_user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(deposit_user_len);
        let deposit_user = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let deposit_amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let withdraw_pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(withdraw_pool_len);
        let withdraw_pool = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = u16::to_u64(app_payload_len);
            app_payload = serde::vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(length == index, EINVALID_LENGTH);

        (deposit_pool, deposit_user, deposit_amount, withdraw_pool, app_id, app_payload)
    }

    /// encode deposit msg
    public fun encode_receive_withdraw_payload(
        source_chain_id: U16,
        nonce: u64,
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        amount: u64
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, source_chain_id);
        serde::serialize_u64(&mut pool_payload, nonce);

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&pool_addr)));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        serde::serialize_u16(&mut pool_payload, u16::from_u64(vector::length(&types::get_dola_address(&user_addr))));
        serde::serialize_vector(&mut pool_payload, types::get_dola_address(&user_addr));

        serde::serialize_u64(&mut pool_payload, amount);

        pool_payload
    }

    /// decode deposit msg
    public fun decode_receive_withdraw_payload(pool_payload: vector<u8>): (U16, u64, DolaAddress, DolaAddress, u64) {
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

        data_len = u16::to_u64(pool_len);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);

        (source_chain_id, nonce, pool_addr, user_addr, amount)
    }
}
