// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Similar to the EVM contract address, using Emitter to represent the contract address in the Dola protocol
module dola_types::dola_contract {
    use sui::event;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const E_ALREADY_REGISTER: u64 = 0;
    const E_NOT_REGITERED: u64 = 1;

    /// Manager for contract address
    struct DolaContractRegistry has key {
        id: UID,
        next_id: u256
    }

    /// Used to represent the contract address in the Dola protocol
    struct DolaContract has store {
        dola_contract_id: u256,
    }

    /// Events

    struct RegisterDolaContract has copy, drop {
        dola_contract_id: u256
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(DolaContractRegistry {
            id: object::new(ctx),
            next_id: 1
        });
    }

    public fun create_dola_contract(): DolaContract {
        DolaContract {
            dola_contract_id: 0
        }
    }

    /// New dola contract address
    public fun register_dola_contract(
        dola_contract_registry: &mut DolaContractRegistry,
        dola_contract: &mut DolaContract
    ) {
        assert!(dola_contract.dola_contract_id == 0, E_ALREADY_REGISTER);
        let dola_contract_id = dola_contract_registry.next_id;
        dola_contract.dola_contract_id = dola_contract_id;
        dola_contract_registry.next_id = dola_contract_id + 1;

        event::emit(RegisterDolaContract { dola_contract_id });
    }

    /// Get dola contract id
    public fun get_dola_contract_id(emitter: &DolaContract): u256 {
        assert!(emitter.dola_contract_id != 0, E_NOT_REGITERED);
        emitter.dola_contract_id
    }

    #[test_only]
    public fun create_for_testing(ctx: &mut TxContext) {
        transfer::share_object(DolaContractRegistry {
            id: object::new(ctx),
            next_id: 0
        });
    }
}

