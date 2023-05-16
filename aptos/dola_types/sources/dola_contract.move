// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Similar to the EVM contract address, using Emitter to represent the contract address in the Dola protocol
module dola_types::dola_contract {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event::{Self, EventHandle};

    const SEED: vector<u8> = b"Dola Contract";

    /// Errors

    const EMUST_ADMIN: u64 = 0;

    const ENOT_INIT: u64 = 1;

    const EHAS_INIT: u64 = 2;

    /// Manager for contract address
    struct DolaContractRegistry has key {
        resource_signer_cap: SignerCapability,
        next_id: u256,
        create_event_handle: EventHandle<CreateDolaContract>
    }

    /// Used to represent the contract address in the Dola protocol
    struct DolaContract has store {
        dola_contract: u256,
    }

    /// Events

    struct CreateDolaContract has drop, store {
        dola_contract: u256
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @dola_types
    }

    public fun ensure_init(): bool {
        exists<DolaContractRegistry>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@dola_types, SEED)
    }

    fun get_resouce_signer(): signer acquires DolaContractRegistry {
        assert!(ensure_init(), ENOT_INIT);
        let dola_contract_registry = borrow_global<DolaContractRegistry>(get_resource_address());
        account::create_signer_with_capability(&dola_contract_registry.resource_signer_cap)
    }

    public entry fun init(sender: &signer) {
        assert!(ensure_admin(sender), EMUST_ADMIN);
        assert!(!ensure_init(), EHAS_INIT);

        let (resource_signer, resource_signer_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, DolaContractRegistry {
            resource_signer_cap,
            next_id: 0,
            create_event_handle: account::new_event_handle(&resource_signer)
        });
    }

    /// New dola contract address
    public fun create_dola_contract(): DolaContract acquires DolaContractRegistry {
        assert!(ensure_init(), ENOT_INIT);
        let dola_contract_registry = borrow_global_mut<DolaContractRegistry>(get_resource_address());
        let dola_contract = dola_contract_registry.next_id;
        dola_contract_registry.next_id = dola_contract + 1;

        let event_handle = borrow_global_mut<DolaContractRegistry>(get_resource_address());

        event::emit_event(&mut event_handle.create_event_handle, CreateDolaContract { dola_contract });


        DolaContract { dola_contract }
    }

    /// Get dola contract
    public fun get_dola_contract(emitter: &DolaContract): u256 {
        emitter.dola_contract
    }
}

