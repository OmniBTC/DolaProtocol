module wormhole_bridge::bridge_core {
    use std::option::{Self, Option};

    use app_manager::app_manager::{Self, AppCap};
    use omnipool::pool::{Self, decode_send_deposit_payload, decode_send_withdraw_payload, decode_send_deposit_and_withdraw_payload, DolaAddress, unpack_dola, pack_dola};
    use pool_manager::pool_manager::{PoolManagerCap, Self, PoolManagerInfo, DolaAddress as ManagerDolaAddress};
    use sui::coin::Coin;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};
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
        pool_manager_cap: Option<PoolManagerCap>,
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<u16, ExternalAddress>,
        // todo! Deleta after wormhole running
        cache_vaas: Table<u64, vector<u8>>
    }

    struct VaaEvent has copy, drop {
        vaa: vector<u8>,
        nonce: u64
    }

    public fun convert_dola_address_into_manager(addr: DolaAddress): ManagerDolaAddress {
        let (dola_id, dola_address) = unpack_dola(addr);
        pool_manager::pack_dola(dola_id, dola_address)
    }

    public fun convert_dola_address_into_pool(addr: ManagerDolaAddress): DolaAddress {
        let (dola_id, dola_address) = pool_manager::unpack_dola(addr);
        pack_dola(dola_id, dola_address)
    }

    public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext) {
        transfer::share_object(
            CoreState {
                id: object::new(ctx),
                pool_manager_cap: option::none(),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty(),
                cache_vaas: table::new(ctx)
            }
        );
    }

    public fun transfer_pool_manage_cap(core_state: &mut CoreState, pool_manager_cap: PoolManagerCap) {
        core_state.pool_manager_cap = option::some(pool_manager_cap);
    }

    public entry fun register_remote_bridge(
        core_state: &mut CoreState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        // todo! change into govern permission

        // todo! consider remote register
        vec_map::insert(
            &mut core_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    public fun receive_deposit(
        _wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        pool_manager_info: &mut PoolManagerInfo,
        ctx: &mut TxContext
    ): (ManagerDolaAddress, ManagerDolaAddress, u64, vector<u8>) {
        assert!(option::is_some(&core_state.pool_manager_cap), EMUST_SOME);
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (pool, user, amount, token_name, app_id, app_payload) =
        //     decode_send_deposit_payload(myvaa::get_payload(&vaa));

        let (pool, user, amount, app_id, app_payload) =
            decode_send_deposit_payload(vaa);
        let pool = convert_dola_address_into_manager(pool);
        let user = convert_dola_address_into_manager(user);
        assert!(app_manager::app_id(app_cap) == app_id, EINVALID_APP);
        pool_manager::add_liquidity(
            option::borrow(&core_state.pool_manager_cap),
            pool_manager_info,
            pool,
            app_manager::app_id(app_cap),
            // todo: use wormhole chainid
            amount,
            ctx
        );
        // myvaa::destroy(vaa);
        (pool, user, amount, app_payload)
    }

    public fun receive_deposit_and_withdraw(
        _wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        pool_manager_info: &mut PoolManagerInfo,
        ctx: &mut TxContext
    ): (ManagerDolaAddress, ManagerDolaAddress, u64, ManagerDolaAddress, ManagerDolaAddress, u16, vector<u8>) {
        assert!(option::is_some(&core_state.pool_manager_cap), EMUST_SOME);
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (pool, user, amount, token_name, app_id, app_payload) =
        //     decode_send_deposit_payload(myvaa::get_payload(&vaa));

        let (deposit_pool, deposit_user, deposit_amount, withdraw_pool, withdraw_user, app_id, app_payload) = decode_send_deposit_and_withdraw_payload(
            vaa
        );
        let deposit_pool = convert_dola_address_into_manager(deposit_pool);
        let deposit_user = convert_dola_address_into_manager(deposit_user);
        let withdraw_pool = convert_dola_address_into_manager(withdraw_pool);
        let withdraw_user = convert_dola_address_into_manager(withdraw_user);
        assert!(app_manager::app_id(app_cap) == app_id, EINVALID_APP);
        pool_manager::add_liquidity(
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
        (deposit_pool, deposit_user, deposit_amount, withdraw_pool, withdraw_user, app_id, app_payload)
    }

    public fun receive_withdraw(
        _wormhole_state: &mut WormholeState,
        _core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        _ctx: &mut TxContext
    ): (ManagerDolaAddress, ManagerDolaAddress, vector<u8>) {
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &core_state.registered_emitters,
        //     &mut core_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (_pool, user, token_name, app_id, app_payload) =
        //     decode_send_withdraw_payload(myvaa::get_payload(&vaa));
        let (pool, user, app_id, app_payload) =
            decode_send_withdraw_payload(vaa);
        let pool = convert_dola_address_into_manager(pool);
        let user = convert_dola_address_into_manager(user);
        assert!(app_manager::app_id(app_cap) == app_id, EINVALID_APP);

        // myvaa::destroy(vaa);
        (pool, user, app_payload)
    }

    public fun send_withdraw(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_address: ManagerDolaAddress,
        // todo: fix address
        user: ManagerDolaAddress,
        amount: u64,
        wormhole_message_fee: Coin<SUI>,
    ) {
        assert!(option::is_some(&core_state.pool_manager_cap), EMUST_SOME);
        pool_manager::remove_liquidity(
            option::borrow(&core_state.pool_manager_cap),
            pool_manager_info,
            pool_address,
            app_manager::app_id(app_cap),
            amount
        );
        let pool_address = convert_dola_address_into_pool(pool_address);
        let user = convert_dola_address_into_pool(user);
        let msg = pool::encode_receive_withdraw_payload(pool_address, user, amount);
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
