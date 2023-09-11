// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::system_core_bool_adapter {
    use sui::event;
    use sui::tx_context::TxContext;

    use boolamt::anchor::GlobalState;

    use dola_protocol::dola_address;
    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::system_codec;
    use dola_protocol::system_core_storage::{Self as storage, Storage};
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::bool_adapter_core::{Self, CoreState};
    use dola_protocol::bool_adapter_verify::{
        check_server_opcode,
        server_opcode_system_binding,
        server_opcode_system_unbinding
    };


    /// Errors
    const EINVALID_CALLTYPE: u64 = 0;

    /// Events

    struct SystemCoreEvent has copy, drop {
        nonce: u64,
        sender: vector<u8>,
        source_chain_id: u16,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    /// === Public Functions ===

    public fun bind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        storage: &Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_system_binding());

        let (sender, app_payload) = bool_adapter_core::receive_message(
            core_state,
            bool_state,
            message_raw,
            signature,
            storage::get_app_cap(storage),
            ctx
        );
        let (source_chain_id, nonce, binded_address, call_type) = system_codec::decode_bind_payload(app_payload);
        assert!(call_type == system_codec::get_binding_type(), EINVALID_CALLTYPE);

        if (sender == binded_address) {
            user_manager::register_dola_user_id(
                user_manager_info,
                sender
            );
        } else {
            user_manager::bind_user_address(
                user_manager_info,
                sender,
                binded_address
            );
        };
        event::emit(SystemCoreEvent {
            nonce,
            sender: dola_address::get_dola_address(&sender),
            source_chain_id,
            user_chain_id: dola_address::get_dola_chain_id(&binded_address),
            user_address: dola_address::get_dola_address(&binded_address),
            call_type
        })
    }

    public fun unbind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        storage: &Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_system_unbinding());

        let (sender, app_payload) = bool_adapter_core::receive_message(
            core_state,
            bool_state,
            message_raw,
            signature,
            storage::get_app_cap(storage),
            ctx
        );
        let (source_chain_id, nonce, unbinded_address, call_type) = system_codec::decode_bind_payload(app_payload);
        assert!(call_type == system_codec::get_unbinding_type(), EINVALID_CALLTYPE);

        user_manager::unbind_user_address(
            user_manager_info,
            sender,
            unbinded_address
        );
        event::emit(SystemCoreEvent {
            nonce,
            sender: dola_address::get_dola_address(&sender),
            source_chain_id,
            user_chain_id: dola_address::get_dola_chain_id(&unbinded_address),
            user_address: dola_address::get_dola_address(&unbinded_address),
            call_type
        })
    }
}
