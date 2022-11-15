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
    use wormhole::external_address::ExternalAddress;
    use wormhole::state::{State as WormholeState};
    use wormhole::myvaa::{Self as vaa};
    use serde::u16;
    use wormhole::external_address;
    use sui::object_table;
    use sui::vec_map::VecMap;
    use sui::vec_map;
    use wormhole_bridge::verify::{parse_verify_and_replay_protect, Unit};

    const EMUST_DEPLOYER: u64 = 0;

    const EUNKNOWN_CHAIN: u64 = 1;

    const EUNKNOWN_EMITTER: u64 = 2;

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

    public entry fun receive<CoinType>(
        wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        vaa: vector<u8>,
        pool: &mut Pool<CoinType>,
        ctx: &mut TxContext
    ) {
        let vaa = parse_verify_and_replay_protect(
            wormhole_state,
            &pool_state.registered_emitters,
            &mut pool_state.consumed_vaas,
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
