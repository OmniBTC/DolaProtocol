// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module system_core::wormhole_adapter {

    use governance::genesis::GovernanceCap;

    use dola_types::dola_address;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use system_core::storage::{Self, StorageCap, Storage};
    use system_core::system_codec;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State as WormholeState;
    use wormhole_adapter_core::wormhole_adapter_core::{Self, CoreState};

    /// Errors
    const EINVALID_CALLTYPE: u64 = 0;

    struct WormholeAdapter has key {
        id: UID,
        storage_cap: StorageCap
    }

    /// Events

    struct SystemCoreEvent has copy, drop {
        nonce: u64,
        sender: vector<u8>,
        source_chain_id: u16,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    public fun initialize_cap_with_governance(
        governance: &GovernanceCap,
        ctx: &mut TxContext
    ) {
        transfer::share_object(WormholeAdapter {
            id: object::new(ctx),
            storage_cap: storage::register_cap_with_governance(governance),
        })
    }

    public entry fun bind_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        wormhole_adapter: &mut WormholeAdapter,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>
    ) {
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(&wormhole_adapter.storage_cap, storage),
            vaa
        );
        let (source_chain_id, nonce, binded_address, call_type) = system_codec::decode_bind_payload(app_payload);
        assert!(call_type == system_codec::get_binding_type(), EINVALID_CALLTYPE);

        if (sender == binded_address) {
            user_manager::register_dola_user_id(
                storage::get_user_manager_cap(&wormhole_adapter.storage_cap, storage),
                user_manager_info,
                sender
            );
        } else {
            user_manager::bind_user_address(
                storage::get_user_manager_cap(&wormhole_adapter.storage_cap, storage),
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
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        wormhole_adapter: &mut WormholeAdapter,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>
    ) {
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(&wormhole_adapter.storage_cap, storage),
            vaa
        );
        let (source_chain_id, nonce, unbinded_address, call_type) = system_codec::decode_bind_payload(app_payload);
        assert!(call_type == system_codec::get_unbinding_type(), EINVALID_CALLTYPE);

        user_manager::unbind_user_address(
            storage::get_user_manager_cap(&wormhole_adapter.storage_cap, storage),
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
