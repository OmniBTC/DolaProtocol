module wormhole_bridge::bridge_core {
    use omnipool::pool;
    use omnipool::pool::Pool;
    use sui::coin::Coin;
    use sui::tx_context::TxContext;
    use wormhole::wormhole;
    use wormhole::emitter::EmitterCapability;
    use sui::transfer;
    use sui::tx_context;
    use sui::sui::SUI;
    use serde::u16::U16;
    use wormhole::external_address::ExternalAddress;
    use wormhole::state::{State as WormholeState};
    use wormhole::myvaa::{Self as vaa};
    use serde::u16;
    use wormhole::external_address;
    use sui::object_table;
    use sui::vec_map::VecMap;
    use sui::vec_map;
    use pool_manager::pool_manager::{PoolManagerCap, Self};
    use wormhole_bridge::verify::{Unit, parse_verify_and_replay_protect};

    const EMUST_DEPLOYER: u64 = 0;

    const EUNKNOWN_CHAIN: u64 = 1;

    const EUNKNOWN_EMITTER: u64 = 2;

    struct CoreState has key, store {
        pool_manager_cap: PoolManagerCap,
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<U16, ExternalAddress>
    }

    public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);
        transfer::share_object(
            CoreState {
                pool_manager_cap: pool_manager::register_cap(ctx),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty()
            }
        );
    }

    public entry fun register_remote_bridge(
        core_state: &mut CoreState,
        emitter_chain_id: u64,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        // todo! change into govern permission
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);

        // todo! consider remote register
        vec_map::insert(
            &mut core_state.registered_emitters,
            u16::from_u64(emitter_chain_id),
            external_address::from_bytes(emitter_address)
        );
    }

    public entry fun send<CoinType>(
        core_state: &mut CoreState,
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
        wormhole::publish_message(&mut core_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
    }

    public entry fun receive<CoinType>(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        vaa: vector<u8>,
        _pool: &mut Pool<CoinType>,
        ctx: &mut TxContext
    ) {
        let vaa = parse_verify_and_replay_protect(
            wormhole_state,
            &core_state.registered_emitters,
            &mut core_state.consumed_vaas,
            vaa,
            ctx
        );
        vaa::destroy(vaa);
    }
}
