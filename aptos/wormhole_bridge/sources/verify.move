module wormhole_bridge::verify {
    use wormhole::external_address::ExternalAddress;
    use std::option::Option;
    use std::option;
    use wormhole::vaa::{Self as vaa, VAA};
    use wormhole::u16::{Self as wormhole_u16};
    use aptos_std::table::Table;
    use aptos_std::table;
    use serde::u16::{U16, Self};
    use wormhole::set::Set;
    use wormhole::set;

    const EUNKNOWN_CHAIN: u64 = 1;

    const EUNKNOWN_EMITTER: u64 = 2;


    public fun get_registered_emitter(
        registered_emitters: &Table<U16, ExternalAddress>,
        chain_id: U16
    ): Option<ExternalAddress> {
        if (table::contains(registered_emitters, chain_id)) {
            option::some(*table::borrow(registered_emitters, chain_id))
        } else {
            option::none()
        }
    }

    public fun assert_known_emitter(registered_emitters: &Table<U16, ExternalAddress>, vm: &VAA) {
        let chain_id = u16::from_u64(wormhole_u16::to_u64(vaa::get_emitter_chain(vm)));
        let maybe_emitter = get_registered_emitter(registered_emitters, chain_id);
        assert!(option::is_some<ExternalAddress>(&maybe_emitter), EUNKNOWN_CHAIN);

        let emitter = option::extract(&mut maybe_emitter);
        assert!(emitter == vaa::get_emitter_address(vm), EUNKNOWN_EMITTER);
    }

    public fun parse_and_verify(
        registered_emitters: &Table<U16, ExternalAddress>,
        vaa: vector<u8>,
    ): VAA {
        let vaa = vaa::parse_and_verify(vaa);
        assert_known_emitter(registered_emitters, &vaa);
        vaa
    }

    public fun replay_protect(consumed_vaas: &mut Set<vector<u8>>, vaa: &VAA) {
        set::add(consumed_vaas, vaa::get_hash(vaa));
    }

    public fun parse_verify_and_replay_protect(
        registered_emitters: &Table<U16, ExternalAddress>,
        consumed_vaas: &mut Set<vector<u8>>,
        vaa: vector<u8>): VAA {
        let vaa = parse_and_verify( registered_emitters, vaa);
        replay_protect(consumed_vaas, &vaa);
        vaa
    }
}
