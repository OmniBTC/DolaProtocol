module wormhole_bridge::bridge_core {
    use std::option::{Self, Option};

    use app_manager::app_manager::{Self, AppCap};
    use dola_types::types::DolaAddress;
    use governance::genesis::GovernanceCap;
    use omnipool::pool::{Self, decode_send_deposit_payload, decode_send_withdraw_payload, decode_send_deposit_and_withdraw_payload};
    use pool_manager::pool_manager::{PoolManagerCap, Self, PoolManagerInfo};
    use sui::coin::Coin;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};
    use user_manager::user_manager::{Self, is_dola_user, UserManagerInfo, register_dola_user_id, UserManagerCap};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::state::State as WormholeState;
    use wormhole::wormhole;
    use wormhole_bridge::verify::Unit;

    const EMUST_DEPLOYER: u64 = 0;

    const EMUST_SOME: u64 = 1;

    const EINVALID_APP: u64 = 2;

    struct CoreState has key, store {
        id: UID,
        user_manager_cap: Option<UserManagerCap>,
        pool_manager_cap: Option<PoolManagerCap>,
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<u16, ExternalAddress>,
        // todo! Delete after wormhole running
        cache_vaas: Table<u64, vector<u8>>
    }

    struct VaaEvent has copy, drop {
        vaa: vector<u8>,
        nonce: u64
    }

    public fun initialize_wormhole_with_governance(
        governance: &GovernanceCap,
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    ) {
        transfer::share_object(
            CoreState {
                id: object::new(ctx),
                user_manager_cap: option::some(user_manager::register_cap_with_governance(governance)),
                pool_manager_cap: option::some(pool_manager::register_cap_with_governance(governance)),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty(),
                cache_vaas: table::new(ctx)
            }
        );
    }

    public fun register_remote_bridge(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        // todo! consider remote register
        vec_map::insert(
            &mut core_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    /// Only verify that the message is valid, and the message is processed by the corresponding app
    public fun receive_protocol_message(
        _wormhole_state: &mut WormholeState,
        _core_state: &mut CoreState,
        vaa: vector<u8>,
    ): vector<u8> {
        // let msg = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        vaa
    }

    public fun receive_deposit(
        _wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        ctx: &mut TxContext
    ): (DolaAddress, DolaAddress, u64, vector<u8>) {
        assert!(option::is_some(&core_state.pool_manager_cap), EMUST_SOME);
        assert!(option::is_some(&core_state.user_manager_cap), EMUST_SOME);
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (pool, user, amount, dola_pool_id, app_id, app_payload) =
        //     decode_send_deposit_payload(myvaa::get_payload(&vaa));

        let (pool, user, amount, app_id, app_payload) =
            decode_send_deposit_payload(vaa);
        assert!(app_manager::app_id(app_cap) == app_id, EINVALID_APP);
        let (actual_amount, _) = pool_manager::add_liquidity(
            option::borrow(&core_state.pool_manager_cap),
            pool_manager_info,
            pool,
            app_manager::app_id(app_cap),
            // todo: use wormhole chainid
            amount,
            ctx
        );
        if (!is_dola_user(user_manager_info, user)) {
            register_dola_user_id(option::borrow(&core_state.user_manager_cap), user_manager_info, user);
        };
        // myvaa::destroy(vaa);
        (pool, user, actual_amount, app_payload)
    }

    public fun receive_deposit_and_withdraw(
        _wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        pool_manager_info: &mut PoolManagerInfo,
        ctx: &mut TxContext
    ): (DolaAddress, DolaAddress, u64, DolaAddress, u16, vector<u8>) {
        assert!(option::is_some(&core_state.pool_manager_cap), EMUST_SOME);
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (pool, user, amount, dola_pool_id, app_id, app_payload) =
        //     decode_send_deposit_payload(myvaa::get_payload(&vaa));

        let (deposit_pool, deposit_user, deposit_amount, withdraw_pool, app_id, app_payload) = decode_send_deposit_and_withdraw_payload(
            vaa
        );
        assert!(app_manager::app_id(app_cap) == app_id, EINVALID_APP);
        let (actual_amount, _) = pool_manager::add_liquidity(
            option::borrow(&core_state.pool_manager_cap),
            pool_manager_info,
            deposit_pool,
            app_manager::app_id(app_cap),
            // todo: use wormhole chainid
            // wormhole_u16::to_u64(myvaa::get_emitter_chain(&vaa)),
            deposit_amount,
            ctx
        );
        // myvaa::destroy(vaa);
        (deposit_pool, deposit_user, actual_amount, withdraw_pool, app_id, app_payload)
    }

    public fun receive_withdraw(
        _wormhole_state: &mut WormholeState,
        _core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        _ctx: &mut TxContext
    ): (DolaAddress, DolaAddress, vector<u8>) {
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (_pool, user, dola_pool_id, app_id, app_payload) =
        //     decode_send_withdraw_payload(myvaa::get_payload(&vaa));
        let (pool, user, app_id, app_payload) =
            decode_send_withdraw_payload(vaa);
        assert!(app_manager::app_id(app_cap) == app_id, EINVALID_APP);

        // myvaa::destroy(vaa);
        (pool, user, app_payload)
    }

    public fun send_withdraw(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_address: DolaAddress,
        // todo: fix address
        user: DolaAddress,
        source_chain_id: u16,
        nonce: u64,
        amount: u64,
        wormhole_message_fee: Coin<SUI>,
    ) {
        assert!(option::is_some(&core_state.pool_manager_cap), EMUST_SOME);
        let (actual_amount, _) = pool_manager::remove_liquidity(
            option::borrow(&core_state.pool_manager_cap),
            pool_manager_info,
            pool_address,
            app_manager::app_id(app_cap),
            amount
        );
        let msg = pool::encode_receive_withdraw_payload(source_chain_id, nonce, pool_address, user, actual_amount);
        wormhole::publish_message(&mut core_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&core_state.cache_vaas) + 1;
        table::add(&mut core_state.cache_vaas, index, msg);
    }

    public entry fun read_vaa(core_state: &CoreState, index: u64) {
        if (index == 0) {
            index = table::length(&core_state.cache_vaas);
        };
        event::emit(VaaEvent {
            vaa: *table::borrow(&core_state.cache_vaas, index),
            nonce: index
        })
    }
}
