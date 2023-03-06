// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Similar to the EVM contract address, using Emitter to represent the contract address in the Dola protocol
module dola_types::emitter {
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;

    struct EmitterRegistry has key {
        id: UID,
        next_id: u256
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(EmitterRegistry {
            id: object::new(ctx),
            next_id: 0
        });
    }


    public fun new_emitter(registry: &mut EmitterRegistry, ctx: &mut TxContext): Emitter {
        let dola_contract = registry.next_id;
        registry.next_id = dola_contract + 1;
        Emitter { id: object::new(ctx), dola_contract }
    }

    struct Emitter has key, store {
        id: UID,
        // Used to represent the contract address in the Dola protocol
        dola_contract: u256,
    }

    public fun get_dola_contract(emitter: &Emitter): u256 {
        emitter.dola_contract
    }
}

