module wormhole_bridge::bridge_pool {
    use omnipool::pool;
    use omnipool::pool::{Pool, PoolMangerCap};
    use sui::coin::Coin;
    use sui::tx_context::TxContext;
    use wormhole::wormhole;
    use wormhole::emitter::EmitterCapability;
    use sui::transfer;
    use sui::tx_context;
    use sui::sui::SUI;
    use serde::u16::U16;
    use wormhole::myu16::{Self as wormhole_u16};
    use wormhole::external_address::ExternalAddress;
    use wormhole::state::{State as WormholeState};
    use wormhole::myvaa::{Self as vaa, VAA};
    use serde::u16;
    use wormhole::external_address;
    use sui::object_table;
    use sui::object::UID;
    use std::option::Option;
    use sui::vec_map::VecMap;
    use sui::vec_map;
    use std::option;
    use sui::object;

    const EMUST_DEPLOYER: u64 = 0;

    const EUNKNOWN_CHAIN: u64 = 1;

    const EUNKNOWN_EMITTER: u64 = 2;

    struct Unit has key, store { id: UID, }

    struct PoolState has key, store {
        pool_cap: PoolMangerCap,
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<U16, ExternalAddress>
    }

    public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);
        transfer::share_object(
            PoolState {
                pool_cap: pool::register_cap(ctx),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty()
            }
        );
    }

    public entry fun register_remote_bridge(
        pool_state: &mut PoolState,
        emitter_chain_id: u64,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        // todo! change into govern permission
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);

        // todo! consider remote register
        vec_map::insert(
            &mut pool_state.registered_emitters,
            u16::from_u64(emitter_chain_id),
            external_address::from_bytes(emitter_address)
        );
    }

    public entry fun send<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = pool::deposit_to<CoinType>(
            pool,
            deposit_coin,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
    }

    public fun get_registered_emitter(pool_state: &PoolState, chain_id: &U16): Option<ExternalAddress> {
        if (vec_map::contains(&pool_state.registered_emitters, chain_id)) {
            option::some(*vec_map::get(&pool_state.registered_emitters, chain_id))
        } else {
            option::none()
        }
    }

    public fun assert_known_emitter(pool_state: &PoolState, vm: &VAA) {
        let chain_id = u16::from_u64(wormhole_u16::to_u64(vaa::get_emitter_chain(vm)));
        let maybe_emitter = get_registered_emitter(pool_state, &chain_id);
        assert!(option::is_some<ExternalAddress>(&maybe_emitter), EUNKNOWN_CHAIN);

        let emitter = option::extract(&mut maybe_emitter);
        assert!(emitter == vaa::get_emitter_address(vm), EUNKNOWN_EMITTER);
    }

    public fun parse_and_verify(
        wormhole_state: &mut WormholeState,
        bridge_state: &PoolState,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ): VAA {
        let vaa = vaa::parse_and_verify(wormhole_state, vaa, ctx);
        assert_known_emitter(bridge_state, &vaa);
        vaa
    }

    public fun replay_protect(pool_state: &mut PoolState, vaa: &VAA, ctx: &mut TxContext) {
        // this calls set::add which aborts if the element already exists
        object_table::add<vector<u8>, Unit>(
            &mut pool_state.consumed_vaas,
            vaa::get_hash(vaa),
            Unit { id: object::new(ctx) }
        );
    }

    public fun parse_verify_and_replay_protect(
        wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        vaa: vector<u8>,
        ctx: &mut TxContext): VAA {
        let vaa = parse_and_verify(wormhole_state, pool_state, vaa, ctx);
        replay_protect(pool_state, &vaa, ctx);
        vaa
    }

    public entry fun receive<CoinType>(
        wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        vaa: vector<u8>,
        pool: &mut Pool<CoinType>,
        ctx: &mut TxContext
    ) {
        let vaa = parse_verify_and_replay_protect(
            wormhole_state,
            pool_state,
            vaa,
            ctx
        );
        // todo! get withdraw return data and process!
        pool::withdraw_to(
            &pool_state.pool_cap,
            pool,
            vaa::get_payload(&vaa),
            ctx
        );
        vaa::destroy(vaa);
    }
}
