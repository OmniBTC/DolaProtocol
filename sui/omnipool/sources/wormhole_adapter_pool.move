// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Wormhole bridge adapter, this module is responsible for adapting wormhole to transmit messages across chains
/// for the Sui single currency pool (distinct from the wormhole adapter core). The main purposes of this module are:
/// 1) Receive AppPalod from the application portal, use single currency pool encoding, and transmit messages;
/// 2) Receive withdrawal messages from bridge core for withdrawal
module omnipool::wormhole_adapter_pool {
    use dola_types::dola_address::{Self, DolaAddress};
    use omnipool::codec_pool;
    use omnipool::single_pool::{Self, Pool, PoolApproval};
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
    use dola_types::dola_contract::{Self, DolaContract, DolaContractRegistry};
    use sui::tx_context;

    const EINVALIE_DOLA_CONTRACT: u64 = 0;

    const EINVALIE_DOLA_CHAIN: u64 = 1;

    const EINVLIAD_SENDER: u64 = 2;

    const EHAS_INIT: u64 = 3;

    /// Reocord genesis of this module
    struct PoolGensis has key {
        id: UID,
        // Record creator of this module
        creator: address,
        // Record whether is initialized
        is_init: bool
    }

    /// `wormhole_bridge_adapter` adapts to wormhole, enabling cross-chain messaging.
    /// For VAA data, the following validations are required.
    /// For wormhole official library: 1) verify the signature.
    /// For wormhole_bridge_adapter itself: 1) make sure it comes from the correct (emitter_chain, wormhole_emitter_address) by
    /// VAA; 2) make sure the data has not been processed by VAA hash;
    struct PoolState has key {
        id: UID,
        /// Used to represent the contract address of this module in the Dola protocol
        dola_contract: DolaContract,
        // Move does not have a contract address, Wormhole uses the emitter
        // in EmitterCapability to represent the send address of this contract
        wormhole_emitter: EmitterCapability,
        // Used to verify that the VAA has been processed
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
        registered_emitters: VecMap<u16, ExternalAddress>,
        // todo! Delete after wormhole running
        cache_vaas: Table<u64, vector<u8>>
    }

    /// Events

    /// Event for pool withdraw
    struct PoolWithdrawEvent has drop, copy {
        nonce: u64,
        source_chain_id: u16,
        dst_chain_id: u16,
        pool_address: vector<u8>,
        receiver: vector<u8>,
        amount: u64
    }

    /// todo! Delete after wormhole running
    struct VaaReciveWithdrawEvent has copy, drop {
        pool_address: DolaAddress,
        user_address: DolaAddress,
        amount: u64
    }

    /// todo! Delete after wormhole running
    struct VaaEvent has copy, drop {
        vaa: vector<u8>,
        nonce: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolGensis {
            id: object::new(ctx),
            creator: tx_context::sender(ctx),
            is_init: false
        });
    }


    /// Initialize cap for remote bridge and single pool
    public entry fun initialize_cap_with_governance(
        pool_genesis: &mut PoolGensis,
        sui_wormhole_chain: u16, // Represents the wormhole chain id of the wormhole adpter core on Sui
        sui_wormhole_address: vector<u8>, // Represents the wormhole contract address of the wormhole adpter core on Sui
        pool_approval: &mut PoolApproval,
        dola_contract_registry: &mut DolaContractRegistry,
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    ) {
        assert!(pool_genesis.creator == tx_context::sender(ctx), EINVLIAD_SENDER);
        assert!(!pool_genesis.is_init, EHAS_INIT);

        // Register wormhole emitter for this module
        let wormhole_emitter = wormhole::register_emitter(wormhole_state, ctx);

        // Register for wormhole adpter core emitter
        let registered_emitters = vec_map::empty();
        vec_map::insert(
            &mut registered_emitters,
            sui_wormhole_chain,
            external_address::from_bytes(sui_wormhole_address)
        );

        // Register owner and spender in single pool
        let dola_contract = dola_contract::create_dola_contract(dola_contract_registry, ctx);
        single_pool::register_basic_bridge(pool_approval, &dola_contract);

        let pool_state = PoolState {
            id: object::new(ctx),
            dola_contract,
            wormhole_emitter,
            consumed_vaas: object_table::new(ctx),
            registered_emitters,
            cache_vaas: table::new(ctx)
        };
        transfer::share_object(pool_state);
        pool_genesis.is_init = true;
    }

    /// Call by governance

    /// Register pool owner by governance
    public fun register_owner(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>,
        new_owner_emitter: &DolaContract
    ) {
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        let (dola_chain_id, dola_contract, _call_type) = codec_pool::decode_register_owner_payload(vaa);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        assert!(dola_contract == dola_contract::get_dola_contract(new_owner_emitter), EINVALIE_DOLA_CONTRACT);
        single_pool::register_owner(pool_approval, &pool_state.dola_contract, new_owner_emitter);
    }

    /// Register pool spender by governance
    public fun register_spender(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>,
        spend_emitter: &DolaContract
    ) {
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        let (dola_chain_id, dola_contract, _call_type) = codec_pool::decode_register_spender_payload(vaa);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        assert!(dola_contract == dola_contract::get_dola_contract(spend_emitter), EINVALIE_DOLA_CONTRACT);
        single_pool::register_spender(pool_approval, &pool_state.dola_contract, spend_emitter);
    }

    /// Delete pool owner by governance
    public fun delete_owner(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>
    ) {
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        let (dola_chain_id, dola_contract, _call_type) = codec_pool::decode_delete_owner_payload(vaa);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        single_pool::delete_owner(pool_approval, &pool_state.dola_contract, dola_contract);
    }

    /// Delete pool spender by governance
    public fun delete_spender(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>
    ) {
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        let (dola_chain_id, dola_contract, _call_type) = codec_pool::decode_delete_spender_payload(vaa);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        single_pool::delete_owner(pool_approval, &pool_state.dola_contract, dola_contract);
    }

    /// Call by application

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
    //     let user_address = tx_context::wormhole_emitter(ctx);
    //     let user_address = convert_address_to_dola(user_address);
    //     let binded_address = create_dola_address(dola_chain_id, binded_address);
    //     let payload = protocol_wormhole_adapter::encode_app_payload(
    //         source_chain_id,
    //         nonce,
    //         call_type,
    //         user_address,
    //         binded_address
    //     );
    //     wormhole::publish_message(&mut pool_state.wormhole_emitter, wormhole_state, 0, payload, wormhole_message_fee);
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
    //     let user_address = tx_context::wormhole_emitter(ctx);
    //     let user_address = convert_address_to_dola(user_address);
    //     let unbinded_address = create_dola_address(dola_chain_id, unbinded_address);
    //     let payload = protocol_wormhole_adapter::encode_app_payload(
    //         source_chain_id,
    //         nonce,
    //         call_type,
    //         user_address,
    //         unbinded_address
    //     );
    //     wormhole::publish_message(&mut pool_state.wormhole_emitter, wormhole_state, 0, payload, wormhole_message_fee);
    //     let index = table::length(&pool_state.cache_vaas) + 1;
    //     table::add(&mut pool_state.cache_vaas, index, payload);
    // }

    /// Send deposit by application
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
        wormhole::publish_message(&mut pool_state.wormhole_emitter, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    /// Send withdraw by application
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
        wormhole::publish_message(&mut pool_state.wormhole_emitter, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    /// Send deposit and withdraw by application
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
        wormhole::publish_message(&mut pool_state.wormhole_emitter, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    /// Receive withdraw
    public entry fun receive_withdraw<CoinType>(
        _wormhole_state: &mut WormholeState,
        pool_approval: &PoolApproval,
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
        let (source_chain_id, nonce, pool_address, receiver, amount, _call_type) =
            codec_pool::decode_receive_withdraw_payload(vaa);
        single_pool::inner_withdraw(
            pool_approval,
            &pool_state.dola_contract,
            pool,
            receiver,
            amount,
            pool_address,
            ctx
        );
        // myvaa::destroy(vaa);

        emit(PoolWithdrawEvent {
            nonce,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&pool_address),
            pool_address: dola_address::get_dola_address(&pool_address),
            receiver: dola_address::get_dola_address(&receiver),
            amount
        })
    }

    /// todo! Delete
    public entry fun read_vaa(pool_state: &PoolState, index: u64) {
        if (index == 0) {
            index = table::length(&pool_state.cache_vaas);
        };
        event::emit(VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index),
            nonce: index
        })
    }

    /// todo! Delete
    public entry fun decode_receive_withdraw_payload(vaa: vector<u8>) {
        let (_, _, pool_address, user_address, amount, _) =
            codec_pool::decode_receive_withdraw_payload(vaa);

        event::emit(VaaReciveWithdrawEvent {
            pool_address,
            user_address,
            amount
        })
    }
}
