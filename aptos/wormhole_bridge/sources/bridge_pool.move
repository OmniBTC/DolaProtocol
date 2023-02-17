module wormhole_bridge::bridge_pool {
    use std::signer;
    use std::vector;

    use aptos_std::table::{Self, Table};
    use aptos_framework::account::{Self, SignerCapability, new_event_handle};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{EventHandle, emit_event};

    use dola_types::types::{DolaAddress, create_dola_address, convert_address_to_dola, encode_dola_address, decode_dola_address, get_native_dola_chain_id, dola_chain_id, dola_address};
    use omnipool::pool::{Self, PoolCap, deposit_and_withdraw, encode_send_withdraw_payload};
    use serde::serde::{serialize_u16, serialize_vector, serialize_u8, vector_slice, deserialize_u16, deserialize_u8, serialize_u64, deserialize_u64};
    use serde::u16::{U16, Self};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::set::{Self, Set};
    use wormhole::state;
    use wormhole::wormhole;

    const PROTOCOL_APP_ID: u64 = 0;

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
        // todo! Delete after wormhole running
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

    struct PoolEventHandle has key {
        pool_withdraw_handle: EventHandle<PoolWithdrawEvent>
    }

    struct PoolWithdrawEvent has drop, store {
        nonce: u64,
        source_chain_id: U16,
        dst_chain_id: U16,
        pool_address: vector<u8>,
        receiver: vector<u8>,
        amount: u64
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

        move_to(sender, PoolEventHandle {
            pool_withdraw_handle: new_event_handle<PoolWithdrawEvent>(sender)
        })
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
        nonce: u64,
        dola_chain_id: u64,
        binded_address: vector<u8>,
    ) acquires PoolState {
        let binded_address = create_dola_address(u16::from_u64(dola_chain_id), binded_address);
        let user = convert_address_to_dola(signer::address_of(sender));
        let msg = encode_protocol_app_payload(
            u16::from_u64(get_native_dola_chain_id()),
            nonce,
            BINDING,
            user,
            binded_address
        );
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public entry fun send_unbinding(
        sender: &signer,
        nonce: u64,
        dola_chain_id: u64,
        unbind_address: vector<u8>
    ) acquires PoolState {
        let unbind_address = create_dola_address(u16::from_u64(dola_chain_id), unbind_address);
        let user = convert_address_to_dola(signer::address_of(sender));
        let msg = encode_protocol_app_payload(
            u16::from_u64(get_native_dola_chain_id()),
            nonce,
            UNBINDING,
            user,
            unbind_address
        );
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

    public fun send_withdraw_remote(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        pool: vector<u8>,
        dst_chain: U16,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let user_addr = convert_address_to_dola(signer::address_of(sender));
        let pool_addr = create_dola_address(dst_chain, pool);
        let msg = encode_send_withdraw_payload(pool_addr, user_addr, app_id, app_payload);
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
    ) acquires PoolState, PoolEventHandle {
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
        let (source_chain_id, nonce, pool_address, receiver, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        pool::inner_withdraw<CoinType>(&pool_state.pool_cap, receiver, amount, pool_address);
        // myvaa::destroy(vaa);
        let event_handle = borrow_global_mut<PoolEventHandle>(@wormhole_bridge);
        emit_event(
            &mut event_handle.pool_withdraw_handle,
            PoolWithdrawEvent {
                nonce,
                source_chain_id,
                dst_chain_id: get_dola_chain_id(&pool_address),
                pool_address: dola_address(&pool_address),
                receiver: dola_address(&receiver),
                amount
            }
        )
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
        let (_, _, pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        move_to(sender, VaaReciveWithdrawEvent {
            pool_address,
            user,
            amount
        })
    }

    public fun encode_protocol_app_payload(
        source_chain_id: U16,
        nonce: u64,
        call_type: u8,
        user: DolaAddress,
        binded_address: DolaAddress
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serialize_u16(&mut payload, u16::from_u64(PROTOCOL_APP_ID));

        serialize_u16(&mut payload, source_chain_id);
        serialize_u64(&mut payload, nonce);

        let user = encode_dola_address(user);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&user)));
        serialize_vector(&mut payload, user);

        let binded_address = encode_dola_address(binded_address);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&binded_address)));
        serialize_vector(&mut payload, binded_address);

        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_protocol_app_payload(payload: vector<u8>): (U16, U16, u64, DolaAddress, DolaAddress, u8) {
        let length = vector::length(&payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let app_id = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let source_chain_id = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = deserialize_u64(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
        let user = decode_dola_address(vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(bind_len);
        let binded_address = decode_dola_address(vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (app_id, source_chain_id, nonce, user, binded_address, call_type)
    }
}
