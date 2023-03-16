// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Verification logic module for Wormhole Vaa. Including 1) verifying the signature; 2) ensuring that the VAA has
/// not been reused; 3) verifying the reliability of the source of the message
module omnipool::wormhole_adapter_verify {
    use wormhole::external_address::ExternalAddress;
    use std::option::{Self, Option};
    use wormhole::vaa::{Self as vaa, VAA};
    use wormhole::u16::{Self as wormhole_u16};
    use aptos_std::table::{Self, Table};
    use wormhole::set::{Self, Set};

    /// Errors

    /// Unkonwn chain
    const EUNKNOWN_CHAIN: u64 = 1;

    /// Unkonwn emitter
    const EUNKNOWN_EMITTER: u64 = 2;

    /// Get wormhole emitter address by wormhole chain id
    public fun get_registered_emitter(
        registered_emitters: &Table<u16, ExternalAddress>,
        chain_id: u16
    ): Option<ExternalAddress> {
        if (table::contains(registered_emitters, chain_id)) {
            option::some(*table::borrow(registered_emitters, chain_id))
        } else {
            option::none()
        }
    }

    /// Ensure known wormhole emitter address by vaa
    public fun assert_known_emitter(registered_emitters: &Table<u16, ExternalAddress>, vm: &VAA) {
        let wormhole_chain_id = (wormhole_u16::to_u64(vaa::get_emitter_chain(vm)) as u16);
        let maybe_emitter = get_registered_emitter(registered_emitters, wormhole_chain_id);
        assert!(option::is_some<ExternalAddress>(&maybe_emitter), EUNKNOWN_CHAIN);

        let emitter = option::extract(&mut maybe_emitter);
        assert!(emitter == vaa::get_emitter_address(vm), EUNKNOWN_EMITTER);
    }

    /// Verify signature and known wormhole emitter
    public fun parse_and_verify(
        registered_emitters: &Table<u16, ExternalAddress>,
        vaa: vector<u8>,
    ): VAA {
        let vaa = vaa::parse_and_verify(vaa);
        assert_known_emitter(registered_emitters, &vaa);
        vaa
    }

    /// Ensure that vaa is not reused
    public fun replay_protect(consumed_vaas: &mut Set<vector<u8>>, vaa: &VAA) {
        set::add(consumed_vaas, vaa::get_hash(vaa));
    }

    /// Parse and verify
    public fun parse_verify_and_replay_protect(
        registered_emitters: &Table<u16, ExternalAddress>,
        consumed_vaas: &mut Set<vector<u8>>,
        vaa: vector<u8>
    ): VAA {
        let vaa = parse_and_verify(registered_emitters, vaa);
        replay_protect(consumed_vaas, &vaa);
        vaa
    }
}
