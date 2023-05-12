// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// System front-end contract portal. Including address binding, etc.
module dola_protocol::system_portal {
    use sui::event::emit;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use dola_protocol::dola_address;
    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::system_codec;
    use dola_protocol::user_manager::{Self, UserManagerInfo, UserManagerCap};

    struct SystemPortal has key {
        id: UID,
        // Allow modification of user_manager storage through UserManagerCap
        user_manager_cap: UserManagerCap,
        // Next nonce
        next_nonce: u64
    }

    /// Events

    // Since the protocol can be directly connected on sui,
    // this is a special event for the sui chain.
    struct SymstemLocalEvent has drop, copy {
        nonce: u64,
        sender: address,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    public fun initialize_cap_with_governance(
        governance: &GovernanceCap,
        ctx: &mut TxContext
    ) {
        transfer::share_object(SystemPortal {
            id: object::new(ctx),
            user_manager_cap: user_manager::register_cap_with_governance(governance),
            next_nonce: 0
        })
    }

    fun get_nonce(system_portal: &mut SystemPortal): u64 {
        let nonce = system_portal.next_nonce;
        system_portal.next_nonce = system_portal.next_nonce + 1;
        nonce
    }

    public entry fun binding(
        system_portal: &mut SystemPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        binded_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let user = dola_address::convert_address_to_dola(sender);
        let bind_dola_address = dola_address::create_dola_address(dola_chain_id, binded_address);
        if (user == bind_dola_address) {
            user_manager::register_dola_user_id(
                &system_portal.user_manager_cap,
                user_manager_info,
                user
            );
        } else {
            user_manager::bind_user_address(
                &system_portal.user_manager_cap,
                user_manager_info,
                user,
                bind_dola_address
            );
        };
        emit(SymstemLocalEvent {
            nonce: get_nonce(system_portal),
            sender,
            user_chain_id: dola_chain_id,
            user_address: binded_address,
            call_type: system_codec::get_binding_type()
        })
    }

    public entry fun unbinding(
        system_portal: &mut SystemPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        unbinded_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let user = dola_address::convert_address_to_dola(sender);
        let unbind_dola_address = dola_address::create_dola_address(dola_chain_id, unbinded_address);
        user_manager::unbind_user_address(
            &system_portal.user_manager_cap,
            user_manager_info,
            user,
            unbind_dola_address
        );

        emit(SymstemLocalEvent {
            nonce: get_nonce(system_portal),
            sender,
            user_chain_id: dola_chain_id,
            user_address: unbinded_address,
            call_type: system_codec::get_unbinding_type()
        })
    }
}
