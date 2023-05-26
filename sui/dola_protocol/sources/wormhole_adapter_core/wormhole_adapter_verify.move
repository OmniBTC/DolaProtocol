// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Verification logic module for Wormhole Vaa. Including 1) verifying the signature; 2) ensuring that the VAA has
/// not been reused; 3) verifying the reliability of the source of the message
module dola_protocol::wormhole_adapter_verify {
    use std::option::{Self, Option};

    use sui::clock::Clock;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};

    use wormhole::bytes32::Bytes32;
    use wormhole::external_address::ExternalAddress;
    use wormhole::state::State;
    use wormhole::vaa::{Self, VAA};

    /// Errors

    /// Unkonwn chain
    const EUNKNOWN_CHAIN: u64 = 1;

    /// Unkonwn emitter
    const EUNKNOWN_EMITTER: u64 = 2;

    /// Replay vaa
    const EREPLAY_VAA: u64 = 3;

    /// Placeholder for map
    struct Unit has key, store { id: UID, }

    /// === Helper Functions ===

    /// Get wormhole emitter address by wormhole chain id
    public fun get_registered_emitter(
        registered_emitters: &VecMap<u16, ExternalAddress>,
        wormhole_chain_id: &u16
    ): Option<ExternalAddress> {
        if (vec_map::contains(registered_emitters, wormhole_chain_id)) {
            option::some(*vec_map::get(registered_emitters, wormhole_chain_id))
        } else {
            option::none()
        }
    }

    /// Ensure known wormhole emitter address by vaa
    public fun assert_known_emitter(registered_emitters: &VecMap<u16, ExternalAddress>, vm: &VAA) {
        let wormhole_chain_id = vaa::emitter_chain(vm);
        let maybe_emitter = get_registered_emitter(registered_emitters, &wormhole_chain_id);
        assert!(option::is_some<ExternalAddress>(&maybe_emitter), EUNKNOWN_CHAIN);

        let emitter = option::extract(&mut maybe_emitter);
        assert!(emitter == vaa::emitter_address(vm), EUNKNOWN_EMITTER);
    }

    /// Verify signature and known wormhole emitter
    public fun parse_and_verify(
        wormhole_state: &mut State,
        registered_emitters: &VecMap<u16, ExternalAddress>,
        vaa: vector<u8>,
        clock: &Clock
    ): VAA {
        let vaa = vaa::parse_and_verify(wormhole_state, vaa, clock);
        assert_known_emitter(registered_emitters, &vaa);
        vaa
    }

    /// Ensure that vaa is not reused
    public fun replay_protect(
        consumed_vaas: &mut object_table::ObjectTable<Bytes32, Unit>,
        vaa: &VAA,
        ctx: &mut TxContext
    ) {
        assert!(!object_table::contains(consumed_vaas, vaa::digest(vaa)), EREPLAY_VAA);
        // this calls set::add which aborts if the element already exists
        object_table::add<Bytes32, Unit>(
            consumed_vaas,
            vaa::digest(vaa),
            Unit { id: object::new(ctx) }
        );
    }

    /// Parse and verify
    public fun parse_verify_and_replay_protect(
        wormhole_state: &mut State,
        registered_emitters: &VecMap<u16, ExternalAddress>,
        consumed_vaas: &mut object_table::ObjectTable<Bytes32, Unit>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): VAA {
        let vaa = parse_and_verify(wormhole_state, registered_emitters, vaa, clock);
        replay_protect(consumed_vaas, &vaa, ctx);
        vaa
    }
}
