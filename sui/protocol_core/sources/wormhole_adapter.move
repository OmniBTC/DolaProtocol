module protocol_core::protocol_wormhole_adapter {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{decode_dola_address, DolaAddress, encode_dola_address, dola_chain_id, dola_address};
    use protocol_core::message_types::{Self, binding_type_id, unbinding_type_id};
    use serde::serde::{deserialize_u16, vector_slice, deserialize_u8, serialize_u16, serialize_vector, serialize_u8, serialize_u64, deserialize_u64};
    use sui::event::emit;
    use sui::object::UID;
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

    public entry fun binding_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        user_binding: &mut WormholeAdapter,
        core_state: &mut CoreState,
        vaa: vector<u8>
    ) {
        let app_payload = bridge_core::receive_protocol_message(wormhole_state, core_state, vaa);
        let (app_id, source_chain_id, nonce, sender, bind_address, call_type) = decode_app_payload(app_payload);
        assert!(app_id == message_types::app_id(), EINVALID_APPID);
        assert!(call_type == binding_type_id(), EINVALID_CALLTYPE);

        if (sender == bind_address) {
            user_manager::register_dola_user_id(
                option::borrow(&user_binding.user_manager_cap),
                user_manager_info,
                sender
            );
        } else {
            user_manager::binding_user_address(
                option::borrow(&user_binding.user_manager_cap),
                user_manager_info,
                sender,
                bind_address
            );
        };
        emit(ProtocolCoreEvent {
            nonce,
            sender: dola_address(&sender),
            source_chain_id,
            user_chain_id: dola_chain_id(&bind_address),
            user_address: dola_address(&bind_address),
            call_type
        })
    }

    public entry fun unbinding_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        user_binding: &mut WormholeAdapter,
        core_state: &mut CoreState,
        vaa: vector<u8>
    ) {
        let app_payload = bridge_core::receive_protocol_message(wormhole_state, core_state, vaa);
        let (app_id, source_chain_id, nonce, sender, unbind_address, call_type) = decode_app_payload(app_payload);
        assert!(app_id == message_types::app_id(), EINVALID_APPID);
        assert!(call_type == unbinding_type_id(), EINVALID_CALLTYPE);

        user_manager::unbinding_user_address(
            option::borrow(&user_binding.user_manager_cap),
            user_manager_info,
            sender,
            unbind_address
        );
        emit(ProtocolCoreEvent {
            nonce,
            sender: dola_address(&sender),
            source_chain_id,
            user_chain_id: dola_chain_id(&unbind_address),
            user_address: dola_address(&unbind_address),
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

        serialize_u16(&mut payload, PROTOCOL_APP_ID);

        serialize_u16(&mut payload, source_chain_id);
        serialize_u64(&mut payload, nonce);

        let user = encode_dola_address(sender);
        serialize_u16(&mut payload, (vector::length(&user) as u16));
        serialize_vector(&mut payload, user);

        let user_address = encode_dola_address(user_address);
        serialize_u16(&mut payload, (vector::length(&user_address) as u16));
        serialize_vector(&mut payload, user_address);

        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(payload: vector<u8>): (u16, u16, u64, DolaAddress, DolaAddress, u8) {
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

        data_len = (user_len as u64);
        let user = decode_dola_address(vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = (bind_len as u64);
        let bind_address = decode_dola_address(vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (app_id, source_chain_id, nonce, user, bind_address, call_type)
    }
}