module wormhole_bridge::bridge_core {
    use omnipool::pool::{decode_send_deposit_payload, decode_send_withdraw_payload};
    use sui::tx_context::TxContext;
    use wormhole::wormhole;
    use wormhole::emitter::EmitterCapability;
    use sui::transfer;
    use sui::tx_context;
    use serde::u16::U16;
    use wormhole::external_address::ExternalAddress;
    use wormhole::state::{State as WormholeState};
    use wormhole::myu16::{Self as wormhole_u16};
    use wormhole::myvaa;
    use serde::u16;
    use wormhole::external_address;
    use sui::object_table;
    use sui::vec_map::VecMap;
    use sui::vec_map;
    use pool_manager::pool_manager::{PoolManagerCap, Self, PoolManagerInfo};
    use wormhole_bridge::verify::{Unit, parse_verify_and_replay_protect};
    use sui::bcs;
    use omnipool::pool;
    use sui::coin::Coin;
    use sui::sui::SUI;

    const EMUST_DEPLOYER: u64 = 0;

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

    public fun receive_deposit<CoinType>(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        vaa: vector<u8>,
        pool_manager_info: &mut PoolManagerInfo,
        ctx: &mut TxContext
    ): vector<u8> {
        let vaa = parse_verify_and_replay_protect(
            wormhole_state,
            &core_state.registered_emitters,
            &mut core_state.consumed_vaas,
            vaa,
            ctx
        );
        let (user, amount, token_name, app_payload) =
            decode_send_deposit_payload(myvaa::get_payload(&vaa));
        pool_manager::add_liquidity(
            &core_state.pool_manager_cap,
            pool_manager_info,
            wormhole_u16::to_u64(myvaa::get_emitter_chain(&vaa)),
            token_name,
            // todo! fix address
            bcs::to_bytes(&user),
            amount,
            ctx
        );
        myvaa::destroy(vaa);
        app_payload
    }

    public fun receive_withdraw(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let vaa = parse_verify_and_replay_protect(
            wormhole_state,
            &core_state.registered_emitters,
            &mut core_state.consumed_vaas,
            vaa,
            ctx
        );
        let (_user, _token_name, app_payload) =
            decode_send_withdraw_payload(myvaa::get_payload(&vaa));

        myvaa::destroy(vaa);
        app_payload
    }

    public fun send_withdraw<CoinType>(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        pool_manager_info: &mut PoolManagerInfo,
        chainid: u64,
        user: address,
        amount: u64,
        token_name: vector<u8>,
        wormhole_message_fee: Coin<SUI>,
    ){
        pool_manager::remove_liquidity(
            &core_state.pool_manager_cap,
            pool_manager_info,
            chainid,
            token_name,
            bcs::to_bytes(&user),
            amount
        );
        let msg = pool::encode_receive_withdraw_payload(user, amount, token_name);
        wormhole::publish_message(&mut core_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
    }
}
