// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::system_core_wormhole_adapter {
    use sui::clock::Clock;
    use sui::event;
    use sui::tx_context::TxContext;

    use dola_protocol::dola_address;
    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::system_codec;
    use dola_protocol::system_core_storage::{Self as storage, Storage};
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::wormhole_adapter_core::{Self, CoreState};
    use wormhole::state::State as WormholeState;

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

    /// === Entry Functions ===

    public entry fun bind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
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

    public entry fun unbind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
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
