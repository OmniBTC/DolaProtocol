module protocol_core::protocol_wormhole_adapter {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{Self, DolaAddress};
    use protocol_core::message_types;
    use serde::serde;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerCap, UserManagerInfo};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    const PROTOCOL_APP_ID: u16 = 0;

    const BINDING: u8 = 5;

    const UNBINDING: u8 = 6;

    /// Errors
    const EINVALID_APPID: u64 = 0;

    const EINVALID_CALLTYPE: u64 = 1;

    const EINVALID_LENGTH: u64 = 2;

    const EMUST_NONE: u64 = 3;

    const EMUST_SOME: u64 = 4;

    struct WormholeAdapter has key {
        id: UID,
        user_manager_cap: Option<UserManagerCap>,
    }

    struct ProtocolCoreEvent has copy, drop {
        nonce: u64,
        sender: vector<u8>,
        source_chain_id: u16,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(WormholeAdapter {
            id: object::new(ctx),
            user_manager_cap: option::none()
        })
    }

    public fun transfer_user_manager_cap(
        wormhole_adapter: &mut WormholeAdapter,
        user_manager_cap: UserManagerCap
    ) {
        assert!(option::is_none(&wormhole_adapter.user_manager_cap), EMUST_NONE);
        option::fill(&mut wormhole_adapter.user_manager_cap, user_manager_cap);
    }

    public entry fun bind_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        wormhole_adapter: &mut WormholeAdapter,
        core_state: &mut CoreState,
        vaa: vector<u8>
    ) {
        let app_payload = bridge_core::receive_app_message(wormhole_state, core_state, vaa);
        let (app_id, source_chain_id, nonce, sender, binded_address, call_type) = decode_app_payload(app_payload);
        assert!(app_id == message_types::app_id(), EINVALID_APPID);
        assert!(call_type == message_types::binding_type_id(), EINVALID_CALLTYPE);

        if (sender == binded_address) {
            user_manager::register_dola_user_id(
                option::borrow(&wormhole_adapter.user_manager_cap),
                user_manager_info,
                sender
            );
        } else {
            user_manager::bind_user_address(
                option::borrow(&wormhole_adapter.user_manager_cap),
                user_manager_info,
                sender,
                binded_address
            );
        };
        event::emit(ProtocolCoreEvent {
            nonce,
            sender: types::get_dola_address(&sender),
            source_chain_id,
            user_chain_id: types::get_dola_chain_id(&binded_address),
            user_address: types::get_dola_address(&binded_address),
            call_type
        })
    }

    public entry fun unbind_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        wormhole_adapter: &mut WormholeAdapter,
        core_state: &mut CoreState,
        vaa: vector<u8>
    ) {
        let app_payload = bridge_core::receive_app_message(wormhole_state, core_state, vaa);
        let (app_id, source_chain_id, nonce, sender, unbinded_address, call_type) = decode_app_payload(app_payload);
        assert!(app_id == message_types::app_id(), EINVALID_APPID);
        assert!(call_type == message_types::unbinding_type_id(), EINVALID_CALLTYPE);

        user_manager::unbind_user_address(
            option::borrow(&wormhole_adapter.user_manager_cap),
            user_manager_info,
            sender,
            unbinded_address
        );
        event::emit(ProtocolCoreEvent {
            nonce,
            sender: types::get_dola_address(&sender),
            source_chain_id,
            user_chain_id: types::get_dola_chain_id(&unbinded_address),
            user_address: types::get_dola_address(&unbinded_address),
            call_type
        })
    }

    public fun encode_app_payload(
        source_chain_id: u16,
        nonce: u64,
        call_type: u8,
        sender: DolaAddress,
        user_address: DolaAddress
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serde::serialize_u16(&mut payload, PROTOCOL_APP_ID);

        serde::serialize_u16(&mut payload, source_chain_id);
        serde::serialize_u64(&mut payload, nonce);

        let user = types::encode_dola_address(sender);
        serde::serialize_u16(&mut payload, (vector::length(&user) as u16));
        serde::serialize_vector(&mut payload, user);

        let user_address = types::encode_dola_address(user_address);
        serde::serialize_u16(&mut payload, (vector::length(&user_address) as u16));
        serde::serialize_vector(&mut payload, user_address);

        serde::serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(payload: vector<u8>): (u16, u16, u64, DolaAddress, DolaAddress, u8) {
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

        data_len = (user_len as u64);
        let user = types::decode_dola_address(serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = (bind_len as u64);
        let binded_address = types::decode_dola_address(serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (app_id, source_chain_id, nonce, user, binded_address, call_type)
    }
}
