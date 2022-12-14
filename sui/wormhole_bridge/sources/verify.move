module wormhole_bridge::verify {
    use sui::vec_map::VecMap;
    use wormhole::external_address::ExternalAddress;
    use std::option::Option;
    use sui::vec_map;
    use std::option;
    use wormhole::myvaa::{Self as vaa, VAA};
    use wormhole::myu16::{Self as wormhole_u16};
    use wormhole::state::{State as WormholeState};
    use sui::tx_context::TxContext;
    use sui::object_table;
    use sui::object::UID;
    use sui::object;

    const EUNKNOWN_CHAIN: u64 = 1;

    const EUNKNOWN_EMITTER: u64 = 2;

    struct Unit has key, store { id: UID, }

    public fun get_registered_emitter(registered_emitters: &VecMap<u16, ExternalAddress>, chain_id: &u16): Option<ExternalAddress> {
        if (vec_map::contains(registered_emitters, chain_id)) {
            option::some(*vec_map::get(registered_emitters, chain_id))
        } else {
            option::none()
        }
    }

    public fun assert_known_emitter(registered_emitters: &VecMap<u16, ExternalAddress>, vm: &VAA) {
        let chain_id = (wormhole_u16::to_u64(vaa::get_emitter_chain(vm)) as u16);
        let maybe_emitter = get_registered_emitter(registered_emitters, &chain_id);
        assert!(option::is_some<ExternalAddress>(&maybe_emitter), EUNKNOWN_CHAIN);

        let emitter = option::extract(&mut maybe_emitter);
        assert!(emitter == vaa::get_emitter_address(vm), EUNKNOWN_EMITTER);
    }

    public fun parse_and_verify(
        wormhole_state: &mut WormholeState,
        registered_emitters: &VecMap<u16, ExternalAddress>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ): VAA {
        let vaa = vaa::parse_and_verify(wormhole_state, vaa, ctx);
        assert_known_emitter(registered_emitters, &vaa);
        vaa
    }

    public fun replay_protect(consumed_vaas: &mut object_table::ObjectTable<vector<u8>, Unit>, vaa: &VAA, ctx: &mut TxContext) {
        // this calls set::add which aborts if the element already exists
        object_table::add<vector<u8>, Unit>(
            consumed_vaas,
            vaa::get_hash(vaa),
            Unit { id: object::new(ctx) }
        );
    }

    public fun parse_verify_and_replay_protect(
        wormhole_state: &mut WormholeState,
        registered_emitters: &VecMap<u16, ExternalAddress>,
        consumed_vaas: &mut object_table::ObjectTable<vector<u8>, Unit>,
        vaa: vector<u8>,
        ctx: &mut TxContext): VAA {
        let vaa = parse_and_verify(wormhole_state, registered_emitters, vaa, ctx);
        replay_protect(consumed_vaas, &vaa, ctx);
        vaa
    }
}
