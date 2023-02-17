module wormhole_bridge::bridge_pool {
    use dola_types::types::{Self, DolaAddress, get_dola_address};
    use governance::genesis::GovernanceCap;
    use omnipool::pool::{Self, Pool, PoolCap, deposit_and_withdraw};
    use sui::coin::Coin;
    use sui::event::{Self, emit};
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

    const EAMOUNT_NOT_ENOUGH: u64 = 0;

    const EAMOUNT_MUST_ZERO: u64 = 1;

    const U64_MAX: u64 = 18446744073709551615;

    struct PoolState has key, store {
        id: UID,
        pool_cap: PoolCap,
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

    struct VaaReciveWithdrawEvent has copy, drop {
        pool_address: DolaAddress,
        user: DolaAddress,
        amount: u64
    }

    struct PoolWithdrawEvent has drop, copy {
        nonce: u64,
        source_chain_id: u16,
        dst_chain_id: u16,
        pool_address: vector<u8>,
        receiver: vector<u8>,
        amount: u64
    }

    public fun initialize_wormhole_with_governance(
        governance: &GovernanceCap,
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    ) {
        transfer::share_object(
            PoolState {
                id: object::new(ctx),
                pool_cap: pool::register_cap(governance, ctx),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty(),
                cache_vaas: table::new(ctx)
            }
        );
    }

    public fun register_remote_bridge(
        _: &GovernanceCap,
        pool_state: &mut PoolState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        // todo! consider remote register
        vec_map::insert(
            &mut pool_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    // public fun send_binding(
    //     pool_state: &mut PoolState,
    //     wormhole_state: &mut WormholeState,
    //     wormhole_message_fee: Coin<SUI>,
    //     nonce: u64,
    //     source_chain_id: u16,
    //     dola_chain_id: u16,
    //     binded_address: vector<u8>,
    //     call_type: u8,
    //     ctx: &mut TxContext
    // ) {
    //     let user = tx_context::sender(ctx);
    //     let user = convert_address_to_dola(user);
    //     let binded_address = create_dola_address(dola_chain_id, binded_address);
    //     let payload = protocol_wormhole_adapter::encode_app_payload(
    //         source_chain_id,
    //         nonce,
    //         call_type,
    //         user,
    //         binded_address
    //     );
    //     wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, payload, wormhole_message_fee);
    //     let index = table::length(&pool_state.cache_vaas) + 1;
    //     table::add(&mut pool_state.cache_vaas, index, payload);
    // }

    // public fun send_unbinding(
    //     pool_state: &mut PoolState,
    //     wormhole_state: &mut WormholeState,
    //     wormhole_message_fee: Coin<SUI>,
    //     nonce: u64,
    //     source_chain_id: u16,
    //     dola_chain_id: u16,
    //     unbind_address: vector<u8>,
    //     call_type: u8,
    //     ctx: &mut TxContext
    // ) {
    //     let user = tx_context::sender(ctx);
    //     let user = convert_address_to_dola(user);
    //     let unbind_address = create_dola_address(dola_chain_id, unbind_address);
    //     let payload = protocol_wormhole_adapter::encode_app_payload(
    //         source_chain_id,
    //         nonce,
    //         call_type,
    //         user,
    //         unbind_address
    //     );
    //     wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, payload, wormhole_message_fee);
    //     let index = table::length(&pool_state.cache_vaas) + 1;
    //     table::add(&mut pool_state.cache_vaas, index, payload);
    // }

    public fun send_deposit<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = pool::deposit_to<CoinType>(
            pool,
            deposit_coin,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public fun send_withdraw<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = pool::withdraw_to<CoinType>(
            pool,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public fun send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        deposit_pool: &mut Pool<DepositCoinType>,
        deposit_coin: Coin<DepositCoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
            deposit_pool,
            deposit_coin,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public entry fun receive_withdraw<CoinType>(
        _wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (_pool_address, user, amount, dola_pool_id) =
        //     pool::decode_receive_withdraw_payload(myvaa::get_payload(&vaa));
        let (source_chain_id, nonce, pool_address, receiver, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        pool::inner_withdraw(&pool_state.pool_cap, pool, receiver, amount, pool_address, ctx);
        // myvaa::destroy(vaa);

        emit(PoolWithdrawEvent {
            nonce,
            source_chain_id,
            dst_chain_id: types::get_dola_chain_id(&pool_address),
            pool_address: get_dola_address(&pool_address),
            receiver: get_dola_address(&receiver),
            amount
        })
    }

    public entry fun read_vaa(pool_state: &PoolState, index: u64) {
        if (index == 0) {
            index = table::length(&pool_state.cache_vaas);
        };
        event::emit(VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index),
            nonce: index
        })
    }

    public entry fun decode_receive_withdraw_payload(vaa: vector<u8>) {
        let (_, _, pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);

        event::emit(VaaReciveWithdrawEvent {
            pool_address,
            user,
            amount
        })
    }
}
