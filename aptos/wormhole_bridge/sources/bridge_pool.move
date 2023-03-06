module wormhole_bridge::bridge_pool {
    use std::signer;
    use std::vector;

    use aptos_std::table::{Self, Table};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};

    use dola_types::types::{Self, DolaAddress};
    use omnipool::pool::{Self, PoolCap};
    use serde::serde;
    use serde::u16::{U16, Self};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::set::{Self, Set};
    use wormhole::state;
    use wormhole::wormhole;

    const SUI_WORMHOLE_EMITTER_CHAIN: u64 = 24;

    const SUI_WORMHOLE_EMITTER_ADDRESS: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000004";

    const PROTOCOL_APP_ID: u64 = 0;

    const EMUST_DEPLOYER: u64 = 0;

    const EMUST_ADMIN: u64 = 1;

    const ENOT_INIT: u64 = 2;

    const EINVALID_LENGTH: u64 = 3;

    const SEED: vector<u8> = b"Dola wormhole_bridge";

    /// `wormhole_bridge` adapts to wormhole, enabling cross-chain messaging.
    /// For VAA data, the following validations are required.
    /// wormhole official library:
    ///     1. verify the signature
    /// Wormhole_bridge itself:
    ///     1. make sure it comes from the correct (emitter_chain, emitter_address) by VAA
    ///     2. make sure the data has not been processed by VAA hash
    ///     3. receive_withdraw_with_payload: reserved for future extensions to ensure the
    /// correctness of the recipient's address
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
        let pool_state = PoolState {
            resource_cap,
            pool_cap: pool::register_cap(sender),
            sender: wormhole_emitter,
            consumed_vaas: set::new<vector<u8>>(),
            registered_emitters: table::new(),
            cache_vaas: table::new(),
            nonce: 0
        };
        table::add(
            &mut pool_state.registered_emitters,
            u16::from_u64(SUI_WORMHOLE_EMITTER_CHAIN),
            external_address::from_bytes(SUI_WORMHOLE_EMITTER_ADDRESS)
        );

        move_to(&resource_signer, pool_state);
        move_to(sender, PoolEventHandle {
            pool_withdraw_handle: account::new_event_handle<PoolWithdrawEvent>(sender)
        })
    }

    public fun send_lending_helper_payload(
        sender: &signer,
        dola_pool_ids: vector<u64>,
        call_type: u8
    ) acquires PoolState {
        let user = types::convert_address_to_dola(signer::address_of(sender));
        let msg = encode_lending_helper_payload(
            user,
            dola_pool_ids,
            call_type
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_protocol_payload(
        sender: &signer,
        nonce: u64,
        dola_chain_id: u64,
        bind_address: vector<u8>,
        call_type: u8
    ) acquires PoolState {
        let bind_address = types::create_dola_address(u16::from_u64(dola_chain_id), bind_address);
        let user = types::convert_address_to_dola(signer::address_of(sender));
        let msg = encode_protocol_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            call_type,
            user,
            bind_address
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

    public fun send_withdraw(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        withdraw_chain_id: U16,
        withdraw_pool_address: vector<u8>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = pool::withdraw_to(
            sender,
            withdraw_chain_id,
            withdraw_pool_address,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_deposit_and_withdraw<DepositCoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_chain_id: U16,
        withdraw_pool_address: vector<u8>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = pool::deposit_and_withdraw<DepositCoinType>(
            sender,
            deposit_coin,
            withdraw_chain_id,
            withdraw_pool_address,
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
        event::emit_event(
            &mut event_handle.pool_withdraw_handle,
            PoolWithdrawEvent {
                nonce,
                source_chain_id,
                dst_chain_id: types::get_dola_chain_id(&pool_address),
                pool_address: types::get_dola_address(&pool_address),
                receiver: types::get_dola_address(&receiver),
                amount
            }
        )
    }

    // public fun receive_withdraw_with_payload<CoinType>(
    //     vaa: vector<u8>,
    // ): (Coin<CoinType>, vector<u8>) acquires PoolState, PoolEventHandle {
    //     // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
    //     // let vaa = parse_verify_and_replay_protect(
    //     //     wormhole_state,
    //     //     &pool_state.registered_emitters,
    //     //     &mut pool_state.consumed_vaas,
    //     //     vaa,
    //     //     ctx
    //     // );
    //     // let (_pool_address, user, amount, token_name) =
    //     //     pool::decode_receive_withdraw_payload(myvaa::get_payload(&vaa));
    //     let (source_chain_id, nonce, pool_address, receiver, amount) =
    //         pool::decode_receive_withdraw_payload(vaa);
    //     let pool_state = borrow_global_mut<PoolState>(get_resource_address());
    //
    //     pool::inner_withdraw<CoinType>(&pool_state.pool_cap, receiver, amount, pool_address);
    //     // myvaa::destroy(vaa);
    //     let event_handle = borrow_global_mut<PoolEventHandle>(@wormhole_bridge);
    //     event::emit_event(
    //         &mut event_handle.pool_withdraw_handle,
    //         PoolWithdrawEvent {
    //             nonce,
    //             source_chain_id,
    //             dst_chain_id: types::get_dola_chain_id(&pool_address),
    //             pool_address: types::get_dola_address(&pool_address),
    //             receiver: types::get_dola_address(&receiver),
    //             amount
    //         }
    //     )
    // }

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

    public fun encode_lending_helper_payload(
        sender: DolaAddress,
        dola_pool_ids: vector<u64>,
        call_type: u8,
    ): vector<u8> {
        let payload = vector::empty<u8>();

        let sender = types::encode_dola_address(sender);
        serde::serialize_u16(&mut payload, u16::from_u64(vector::length(&sender)));
        serde::serialize_vector(&mut payload, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        serde::serialize_u16(&mut payload, u16::from_u64(pool_ids_length));
        let i = 0;
        while (i < pool_ids_length) {
            serde::serialize_u16(&mut payload, u16::from_u64(*vector::borrow(&dola_pool_ids, i)));
            i = i + 1;
        };

        serde::serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_lending_helper_payload(
        payload: vector<u8>
    ): (DolaAddress, vector<U16>, u8) {
        let index = 0;
        let data_len;

        data_len = 2;
        let sender_length = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(sender_length);
        let sender = types::decode_dola_address(serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let pool_ids_length = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        let i = 0;
        let dola_pool_ids = vector::empty<U16>();
        while (i < u16::to_u64(pool_ids_length)) {
            data_len = 2;
            let dola_pool_id = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
            vector::push_back(&mut dola_pool_ids, dola_pool_id);
            index = index + data_len;
            i = i + 1;
        };

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&payload), EINVALID_LENGTH);
        (sender, dola_pool_ids, call_type)
    }

    public fun encode_protocol_app_payload(
        source_chain_id: U16,
        nonce: u64,
        call_type: u8,
        user: DolaAddress,
        binded_address: DolaAddress
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serde::serialize_u16(&mut payload, u16::from_u64(PROTOCOL_APP_ID));

        serde::serialize_u16(&mut payload, source_chain_id);
        serde::serialize_u64(&mut payload, nonce);

        let user = types::encode_dola_address(user);
        serde::serialize_u16(&mut payload, u16::from_u64(vector::length(&user)));
        serde::serialize_vector(&mut payload, user);

        let binded_address = types::encode_dola_address(binded_address);
        serde::serialize_u16(&mut payload, u16::from_u64(vector::length(&binded_address)));
        serde::serialize_vector(&mut payload, binded_address);

        serde::serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_protocol_app_payload(payload: vector<u8>): (U16, U16, u64, DolaAddress, DolaAddress, u8) {
        let length = vector::length(&payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let source_chain_id = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = serde::deserialize_u64(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_len);
        let user = types::decode_dola_address(serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(bind_len);
        let binded_address = types::decode_dola_address(serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (app_id, source_chain_id, nonce, user, binded_address, call_type)
    }
}
