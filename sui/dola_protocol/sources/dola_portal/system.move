// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// System front-end contract portal. Including address binding, etc.
module dola_protocol::system_portal {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::genesis::GovernanceGenesis;
    use dola_protocol::user_manager::UserManagerInfo;

    const DEPRECATED: u64 = 0;

    struct SystemPortal has key {
        id: UID,
        // Next nonce
        next_nonce: u64
    }

    /// Events

    // Since the protocol can be directly connected on sui,
    // this is a special event for the sui chain.
    struct SystemLocalEvent has drop, copy {
        nonce: u64,
        sender: address,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(SystemPortal {
            id: object::new(ctx),
            next_nonce: 0
        })
    }

    fun get_nonce(system_portal: &mut SystemPortal): u64 {
        let nonce = system_portal.next_nonce;
        system_portal.next_nonce = system_portal.next_nonce + 1;
        nonce
    }

    /// === Entry Functions ===

    public entry fun binding(
        _genesis: &GovernanceGenesis,
        _system_portal: &mut SystemPortal,
        _user_manager_info: &mut UserManagerInfo,
        _dola_chain_id: u16,
        _binded_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun unbinding(
        _genesis: &GovernanceGenesis,
        _system_portal: &mut SystemPortal,
        _user_manager_info: &mut UserManagerInfo,
        _dola_chain_id: u16,
        _unbinded_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }
}
