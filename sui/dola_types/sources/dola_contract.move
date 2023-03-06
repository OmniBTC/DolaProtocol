// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Similar to the EVM contract address, using Emitter to represent the contract address in the Dola protocol
module dola_types::dola_contract {
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::event;

    /// Manager for contract address
    struct DolaContractRegistry has key {
        id: UID,
        next_id: u256
    }

    /// Used to represent the contract address in the Dola protocol
    struct DolaContract has key, store {
        id: UID,
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
        ctx: &mut TxContext
    ): DolaContract {
        let dola_contract = dola_contract_registry.next_id;
        dola_contract_registry.next_id = dola_contract + 1;

        event::emit(CreateDolaContract { dola_contract });

        DolaContract { id: object::new(ctx), dola_contract }
    }

    /// Get dola contract
    public fun get_dola_contract(emitter: &DolaContract): u256 {
        emitter.dola_contract
    }
}

