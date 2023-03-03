// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Wormhole bridge adapter, this module is responsible for adapting wormhole to transmit messages across chains
/// for the Sui single currency pool (distinct from the wormhole adapter core). The main purposes of this module are:
/// 1) Receive AppPalod from the application portal, use single currency pool encoding, and transmit messages;
/// 2) Receive withdrawal messages from bridge core for withdrawal
module omnipool::wormhole_adapter_pool {
    use dola_types::types::{Self, DolaAddress};
    use omnipool::codec_pool;
    use omnipool::single_pool::{Self, Pool, PoolCap};
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
    use omnipool::wormhole_adapter_verify::Unit;

    const EAMOUNT_NOT_ENOUGH: u64 = 0;

    const EAMOUNT_MUST_ZERO: u64 = 1;

    const U64_MAX: u64 = 18446744073709551615;

    const SUI_EMITTER_CHAIN: u16 = 24;

    const SUI_EMITTER_ADDRESS: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000004";

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
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    ) {
        let pool_state = PoolState {
            id: object::new(ctx),
            pool_cap: single_pool::register_cap(ctx),
            sender: wormhole::register_emitter(wormhole_state, ctx),
            consumed_vaas: object_table::new(ctx),
            registered_emitters: vec_map::empty(),
            cache_vaas: table::new(ctx)
        };
        vec_map::insert(
            &mut pool_state.registered_emitters,
            SUI_EMITTER_CHAIN,
            external_address::from_bytes(SUI_EMITTER_ADDRESS)
        );
        transfer::share_object(pool_state);
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
    //     unbinded_address: vector<u8>,
    //     call_type: u8,
    //     ctx: &mut TxContext
    // ) {
    //     let user = tx_context::sender(ctx);
    //     let user = convert_address_to_dola(user);
    //     let unbinded_address = create_dola_address(dola_chain_id, unbinded_address);
    //     let payload = protocol_wormhole_adapter::encode_app_payload(
    //         source_chain_id,
    //         nonce,
    //         call_type,
    //         user,
    //         unbinded_address
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
        let msg = single_pool::deposit_to<CoinType>(
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

    public fun send_withdraw(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        withdraw_chain_id: u16,
        withdraw_pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = single_pool::withdraw_to(
            withdraw_chain_id,
            withdraw_pool_address,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public fun send_deposit_and_withdraw<DepositCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        deposit_pool: &mut Pool<DepositCoinType>,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_chain_id: u16,
        withdraw_pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = single_pool::deposit_and_withdraw<DepositCoinType>(
            deposit_pool,
            deposit_coin,
            withdraw_chain_id,
            withdraw_pool_address,
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
            codec_pool::decode_receive_withdraw_payload(vaa);
        single_pool::inner_withdraw(&pool_state.pool_cap, pool, receiver, amount, pool_address, ctx);
        // myvaa::destroy(vaa);

        emit(PoolWithdrawEvent {
            nonce,
            source_chain_id,
            dst_chain_id: types::get_dola_chain_id(&pool_address),
            pool_address: types::get_dola_address(&pool_address),
            receiver: types::get_dola_address(&receiver),
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
            codec_pool::decode_receive_withdraw_payload(vaa);

        event::emit(VaaReciveWithdrawEvent {
            pool_address,
            user,
            amount
        })
    }
}
