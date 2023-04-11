// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Similar to the EVM contract address, using Emitter to represent the contract address in the Dola protocol
module dola_types::dola_contract {
    use sui::event;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    /// Manager for contract address
    struct DolaContractRegistry has key {
        id: UID,
        next_id: u256
    }

    /// Used to represent the contract address in the Dola protocol
    struct DolaContract has store {
        dola_contract: u256,
    }

    /// Events

    struct CreateDolaContract has copy, drop {
        dola_contract: u256
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(DolaContractRegistry {
            id: object::new(ctx),
            next_id: 0
        });
    }

    /// New dola contract address
    public fun create_dola_contract(
        dola_contract_registry: &mut DolaContractRegistry,
    ): DolaContract {
        let dola_contract = dola_contract_registry.next_id;
        dola_contract_registry.next_id = dola_contract + 1;

        event::emit(CreateDolaContract { dola_contract });

        DolaContract { dola_contract }
    }

    /// Get dola contract
    public fun get_dola_contract(emitter: &DolaContract): u256 {
        emitter.dola_contract
    }

    #[test_only]
    public fun create_for_testing(ctx: &mut TxContext) {
        transfer::share_object(DolaContractRegistry {
            id: object::new(ctx),
            next_id: 0
        });
    }
}

