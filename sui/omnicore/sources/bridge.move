module wormhole_bridge::bridge {
    use std::option::{Self, Option};
    use std::vector;

    use omnicore::messagecore::process_payload;
    use serde::u16::{Self, U16};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::myu16::Self as wormhole_u16;
    use wormhole::myvaa::{Self as vaa, VAA};
    use wormhole::state::State as WormholeState;
    use wormhole::wormhole;

    const EMUST_DEPLOYER: u64 = 0;

    const EUNKNOWN_CHAIN: u64 = 1;

    const EUNKNOWN_EMITTER: u64 = 2;

    struct Unit has key, store { id: UID, }

    struct State has key, store {
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<U16, ExternalAddress>
    }

    public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);
        transfer::share_object(
            State {
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty()
            }
        );
    }

    public entry fun register_remote_bridge(
        state: &mut State,
        emitter_chain_id: u64,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        // todo! change into govern permission
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);

        // todo! consider remote register
        vec_map::insert(
            &mut state.registered_emitters,
            u16::from_u64(emitter_chain_id),
            external_address::from_bytes(emitter_address)
        );
    }

    public entry fun send(
        state: &mut State,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        msg: vector<u8>,
        _ctx: &mut TxContext
    ) {
        wormhole::publish_message(&mut state.sender, wormhole_state, 0, msg, wormhole_message_fee);
    }

    public fun get_registered_emitter(state: &State, chain_id: &U16): Option<ExternalAddress> {
        if (vec_map::contains(&state.registered_emitters, chain_id)) {
            option::some(*vec_map::get(&state.registered_emitters, chain_id))
        } else {
            option::none()
        }
    }

    public fun assert_known_emitter(state: &State, vm: &VAA) {
        let chain_id = u16::from_u64(wormhole_u16::to_u64(vaa::get_emitter_chain(vm)));
        let maybe_emitter = get_registered_emitter(state, &chain_id);
        assert!(option::is_some<ExternalAddress>(&maybe_emitter), EUNKNOWN_CHAIN);

        let emitter = option::extract(&mut maybe_emitter);
        assert!(emitter == vaa::get_emitter_address(vm), EUNKNOWN_EMITTER);
    }

    public fun parse_and_verify(
        wormhole_state: &mut WormholeState,
        bridge_state: &State,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ): VAA {
        let vaa = vaa::parse_and_verify(wormhole_state, vaa, ctx);
        assert_known_emitter(bridge_state, &vaa);
        vaa
    }

    public fun replay_protect(state: &mut State, vaa: &VAA, ctx: &mut TxContext) {
        // this calls set::add which aborts if the element already exists
        object_table::add<vector<u8>, Unit>(
            &mut state.consumed_vaas,
            vaa::get_hash(vaa),
            Unit { id: object::new(ctx) }
        );
    }

    public fun parse_verify_and_replay_protect(
        wormhole_state: &mut WormholeState,
        state: &mut State,
        vaa: vector<u8>,
        ctx: &mut TxContext): VAA {
        let vaa = parse_and_verify(wormhole_state, state, vaa, ctx);
        replay_protect(state, &vaa, ctx);
        vaa
    }

    public entry fun receive<CoinType>(
        state: &mut State,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        vaa_bytes: vector<u8>,
        ctx: &mut TxContext
    ) {
        let vaa = parse_verify_and_replay_protect(
            wormhole_state,
            state,
            vaa_bytes,
            ctx
        );
        let payload = process_payload(vaa::get_payload(&vaa));
        vaa::destroy(vaa);
        if (vector::length(&payload) > 0) {
            send(state, wormhole_state, wormhole_message_fee, payload, ctx);
        }
    }
}
