module wormhole_bridge::bridge_pool {
    use omnipool::pool::{Self, PoolCap, deposit_and_withdraw};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::wormhole;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use wormhole::set::Set;
    use aptos_std::table::Table;
    use serde::u16::{U16, Self};
    use serde::serde::{serialize_u16, serialize_vector, serialize_u8, vector_slice, deserialize_u16, deserialize_u8};
    use wormhole::set;
    use aptos_std::table;
    use aptos_framework::coin::Coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use dola_types::types::{DolaAddress, create_dola_address, convert_address_to_dola, encode_dola_address, decode_dola_address};
    use aptos_framework::coin;
    use wormhole::state;
    use std::vector;

    const BINDING: u8 = 5;

    const UNBINDING: u8 = 6;

    const EMUST_DEPLOYER: u64 = 0;

    const EMUST_ADMIN: u64 = 1;

    const ENOT_INIT: u64 = 2;

    const EINVALID_LENGTH: u64 = 3;

    const SEED: vector<u8> = b"Dola wormhole_bridge";

    struct PoolState has key, store {
        resource_cap: SignerCapability,
        pool_cap: PoolCap,
        sender: EmitterCapability,
        consumed_vaas: Set<vector<u8>>,
        registered_emitters: Table<U16, ExternalAddress>,
        // todo! Deleta after wormhole running
        cache_vaas: Table<u64, vector<u8>>,
        nonce: u64
    }

    struct VaaEvent has key, copy, drop {
        vaa: vector<u8>,
        nonce: u64
    }

    struct VaaReciveWithdrawEvent has key, copy, drop {
        pool_address: DolaAddress,
        user: DolaAddress,
        amount: u64,
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @wormhole_bridge
    }

    public fun ensure_init(): bool {
        exists<PoolState>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@wormhole_bridge, SEED)
    }

    public entry fun initialize_wormhole(sender: &signer) {
        assert!(ensure_admin(sender), EMUST_ADMIN);
        assert!(!ensure_init(), ENOT_INIT);

        let wormhole_emitter = wormhole::register_emitter();
        let (resource_signer, resource_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, PoolState {
            resource_cap,
            pool_cap: pool::register_cap(sender),
            sender: wormhole_emitter,
            consumed_vaas: set::new<vector<u8>>(),
            registered_emitters: table::new(),
            cache_vaas: table::new(),
            nonce: 0
        });
    }

    public fun register_remote_bridge(
        sender: &signer,
        emitter_chain_id: U16,
        emitter_address: vector<u8>,
    ) acquires PoolState {
        // todo! change into govern permission
        assert!(ensure_admin(sender), EMUST_ADMIN);

        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // todo! consider remote register
        table::add(
            &mut pool_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    public entry fun send_binding(
        sender: &signer,
        dola_chain_id: u64,
        bind_address: vector<u8>,
    ) acquires PoolState {
        let bind_address = create_dola_address(u16::from_u64(dola_chain_id), bind_address);
        let user = convert_address_to_dola(signer::address_of(sender));
        let msg = encode_binding(user, bind_address);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public entry fun send_unbinding(
        sender: &signer,
        dola_chain_id: u64,
        unbind_address: vector<u8>
    ) acquires PoolState {
        let unbind_address = create_dola_address(u16::from_u64(dola_chain_id), unbind_address);
        let user = convert_address_to_dola(signer::address_of(sender));
        let msg = encode_unbinding(user, unbind_address);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_deposit<CoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        deposit_coin: Coin<CoinType>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = pool::deposit_to<CoinType>(
            sender,
            deposit_coin,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_withdraw<CoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = pool::withdraw_to<CoinType>(
            sender,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        deposit_coin: Coin<DepositCoinType>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
            sender,
            deposit_coin,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public entry fun receive_withdraw<CoinType>(
        vaa: vector<u8>,
    ) acquires PoolState {
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (_pool_address, user, amount, token_name) =
        //     pool::decode_receive_withdraw_payload(myvaa::get_payload(&vaa));
        let (pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        pool::inner_withdraw<CoinType>(&pool_state.pool_cap, user, amount, pool_address);
        // myvaa::destroy(vaa);
    }

    public entry fun read_vaa(sender: &signer, index: u64) acquires PoolState {
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        if (index == 0) {
            index = pool_state.nonce;
        };
        move_to(sender, VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index),
            nonce: index
        });
    }

    public entry fun decode_receive_withdraw_payload(sender: &signer, vaa: vector<u8>) {
        let (pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        move_to(sender, VaaReciveWithdrawEvent {
            pool_address,
            user,
            amount
        })
    }

    public fun encode_binding(user: DolaAddress, bind_address: DolaAddress): vector<u8> {
        let binding_payload = vector::empty<u8>();

        let user = encode_dola_address(user);
        serialize_u16(&mut binding_payload, u16::from_u64(vector::length(&user)));
        serialize_vector(&mut binding_payload, user);

        let bind_address = encode_dola_address(bind_address);
        serialize_u16(&mut binding_payload, u16::from_u64(vector::length(&bind_address)));
        serialize_vector(&mut binding_payload, bind_address);

        serialize_u8(&mut binding_payload, BINDING);
        binding_payload
    }

    public fun decode_binding(binding_payload: vector<u8>): (DolaAddress, DolaAddress, u8) {
        let length = vector::length(&binding_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
        let user = decode_dola_address(vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = deserialize_u16(&vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(bind_len);
        let bind_address = decode_dola_address(vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (user, bind_address, call_type)
    }

    public fun encode_unbinding(user: DolaAddress,unbind_address: DolaAddress): vector<u8> {
        let unbinding_payload = vector::empty<u8>();

        let user = encode_dola_address(user);
        serialize_u16(&mut unbinding_payload, u16::from_u64(vector::length(&user)));
        serialize_vector(&mut unbinding_payload, user);

        let unbind_address = encode_dola_address(unbind_address);
        serialize_u16(&mut unbinding_payload, u16::from_u64(vector::length(&unbind_address)));
        serialize_vector(&mut unbinding_payload, unbind_address);

        serialize_u8(&mut unbinding_payload, UNBINDING);
        unbinding_payload
    }

    public fun decode_unbinding(unbinding_payload: vector<u8>): (DolaAddress, DolaAddress, u8) {
        let length = vector::length(&unbinding_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
        let user = decode_dola_address(vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let unbind_len = deserialize_u16(&vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(unbind_len);
        let unbind_address = decode_dola_address(vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (user, unbind_address, call_type)
    }
}
