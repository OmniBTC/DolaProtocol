// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Wormhole bridge adapter, this module is responsible for adapting wormhole to transmit messages across chains
/// for the Sui dola pool (distinct from the wormhole adapter core). The main purposes of this module are:
/// 1) Receive AppPalod from the application portal, use dola pool encoding, and transmit messages;
/// 2) Receive withdrawal messages from bridge core for withdrawal
module dola_protocol::wormhole_adapter_pool {
    use std::vector;

    use sui::clock::Clock;
    use sui::coin;
    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use dola_protocol::dola_address;
    use dola_protocol::dola_pool::{Self, Pool};
    use dola_protocol::genesis::{Self, GovernanceCap, GovernanceGenesis};
    use dola_protocol::pool_codec;
    use dola_protocol::wormhole_adapter_verify::{Self, Unit};
    use wormhole::bytes32::{Self, Bytes32};
    use wormhole::emitter::{Self, EmitterCap};
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::publish_message;
    use wormhole::state::State as WormholeState;
    use wormhole::vaa;

    friend dola_protocol::lending_portal_v2;
    friend dola_protocol::system_portal_v2;

    /// Errors

    const EINVALIE_DOLA_CONTRACT: u64 = 0;

    const EINVALIE_DOLA_CHAIN: u64 = 1;

    const EINVLIAD_SENDER: u64 = 2;

    const EHAS_INIT: u64 = 3;

    const EINVALID_CALL_TYPE: u64 = 4;

    const EDUPLICATED_RELAYER: u64 = 5;

    const ENOT_RELAYER: u64 = 6;

    const ERELAYER_NOT_INIT: u64 = 7;

    const ERELAYER_NOT_EXIST: u64 = 8;

    const ENOT_ENOUGH_WORMHOLE_FEE: u64 = 9;

    /// Reocord genesis of this module
    struct PoolGenesis has key {
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
        // Move does not have a contract address, Wormhole uses the emitter
        // in EmitterCapability to represent the send address of this contract
        wormhole_emitter: EmitterCap,
        // Used to verify that the VAA has been processed
        consumed_vaas: object_table::ObjectTable<Bytes32, Unit>,
        // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
        registered_emitters: VecMap<u16, ExternalAddress>,
    }

    /// Only certain users are allowed to act as Relayer
    struct Relayer has copy, drop, store {}

    /// Nonce for bridge pool
    struct Nonce has copy, drop, store {}

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

    /// Event for add relayer
    struct AddRelayer has drop, copy {
        new_relayer: address
    }

    /// Event for remove relayer
    struct RemoveRelayer has drop, copy {
        removed_relayer: address
    }

    /// Relay Event
    struct RelayEvent has drop, copy {
        // Wormhole vaa sequence
        sequence: u64,
        // Transaction nonce
        nonce: u64,
        // Relay fee amount
        fee_amount: u64,
        // App id
        app_id: u16,
        // Confirm that nonce is in the pool or core
        call_type: u8
    }

    /// === Initial Functions ===

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolGenesis {
            id: object::new(ctx),
            creator: tx_context::sender(ctx),
            is_init: false
        });
    }

    /// Initialize for remote bridge and dola pool
    public entry fun initialize(
        pool_genesis: &mut PoolGenesis,
        sui_wormhole_chain: u16, // Represents the wormhole chain id of the wormhole adpter core on Sui
        sui_wormhole_address: vector<u8>, // Represents the wormhole contract address of the wormhole adpter core on Sui
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    ) {
        assert!(pool_genesis.creator == tx_context::sender(ctx), EINVLIAD_SENDER);
        assert!(!pool_genesis.is_init, EHAS_INIT);

        // Register wormhole emitter for this module
        let wormhole_emitter = emitter::new(wormhole_state, ctx);

        // Register for wormhole adpter core emitter
        let registered_emitters = vec_map::empty();
        vec_map::insert(
            &mut registered_emitters,
            sui_wormhole_chain,
            external_address::new(bytes32::new(sui_wormhole_address))
        );

        // Register owner and spender in dola pool
        let pool_state = PoolState {
            id: object::new(ctx),
            wormhole_emitter,
            consumed_vaas: object_table::new(ctx),
            registered_emitters
        };
        transfer::share_object(pool_state);
        pool_genesis.is_init = true;
    }

    /// === Governance Functions ===

    public fun add_relayer(
        _: &GovernanceCap,
        pool_state: &mut PoolState,
        relayer: address
    ) {
        if (dynamic_field::exists_with_type<Relayer, vector<address>>(&mut pool_state.id, Relayer {})) {
            let relayers = dynamic_field::borrow_mut<Relayer, vector<address>>(&mut pool_state.id, Relayer {});
            assert!(!vector::contains(relayers, &relayer), EDUPLICATED_RELAYER);
            vector::push_back(relayers, relayer);
        } else {
            dynamic_field::add<Relayer, vector<address>>(&mut pool_state.id, Relayer {}, vector[relayer]);
        };
        emit(AddRelayer {
            new_relayer: relayer
        });
    }

    public fun remove_relayer(
        _: &GovernanceCap,
        pool_state: &mut PoolState,
        relayer: address
    ) {
        assert!(
            dynamic_field::exists_with_type<Relayer, vector<address>>(&mut pool_state.id, Relayer {}),
            ERELAYER_NOT_INIT
        );
        let relayers = dynamic_field::borrow_mut<Relayer, vector<address>>(&mut pool_state.id, Relayer {});
        assert!(vector::contains(relayers, &relayer), ERELAYER_NOT_EXIST);
        let (_, index) = vector::index_of(relayers, &relayer);
        vector::remove(relayers, index);
        emit(RemoveRelayer {
            removed_relayer: relayer
        });
    }

    /// === Friend Functions ===

    /// Send deposit by application
    public(friend) fun send_deposit<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        let msg = dola_pool::deposit<CoinType>(
            pool,
            deposit_coin,
            app_id,
            app_payload,
            ctx
        );

        let message_ticket = publish_message::prepare_message(
            &mut pool_state.wormhole_emitter,
            0,
            msg
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        )
    }

    /// Send message that do not involve incoming or outgoing funds by application
    public(friend) fun send_message(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        app_id: u16,
        app_payload: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        let msg = dola_pool::send_message(
            app_id,
            app_payload,
            ctx
        );
        let message_ticket = publish_message::prepare_message(
            &mut pool_state.wormhole_emitter,
            0,
            msg
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        )
    }

    public(friend) fun get_nonce(pool_state: &mut PoolState): u64 {
        if (dynamic_field::exists_with_type<Nonce, u64>(&mut pool_state.id, Nonce {})) {
            let nonce = dynamic_field::remove<Nonce, u64>(&mut pool_state.id, Nonce {});
            let next_nonce = nonce + 1;
            dynamic_field::add<Nonce, u64>(&mut pool_state.id, Nonce {}, next_nonce);
            nonce
        } else {
            dynamic_field::add<Nonce, u64>(&mut pool_state.id, Nonce {}, 0);
            0
        }
    }

    public(friend) fun get_relay_fee_amount(
        wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        nonce: u64,
        bridge_fee: Coin<SUI>,
        ctx: &mut TxContext
    ): (Coin<SUI>, u64) {
        let bridge_fee_amount = coin::value(&bridge_fee);
        let wormhole_fee_amount = wormhole::state::message_fee(wormhole_state);
        assert!(bridge_fee_amount >= wormhole_fee_amount, ENOT_ENOUGH_WORMHOLE_FEE);
        let wormhole_fee = coin::split(&mut bridge_fee, wormhole_fee_amount, ctx);
        let relay_fee_amount = coin::value(&bridge_fee);

        // transfer relay fee to relayer
        let relayer = get_one_relayer(pool_state, nonce);
        transfer::public_transfer(bridge_fee, relayer);

        (wormhole_fee, relay_fee_amount)
    }

    public(friend) fun emit_relay_event(
        sequence: u64,
        nonce: u64,
        fee_amount: u64,
        app_id: u16,
        call_type: u8
    ) {
        emit(RelayEvent {
            sequence,
            nonce,
            fee_amount,
            app_id,
            call_type
        });
    }

    /// === Entry Functions ===

    /// Receive withdraw
    public entry fun receive_withdraw<CoinType>(
        genesis: &GovernanceGenesis,
        wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        check_relayer(pool_state, ctx);
        let vaa = wormhole_adapter_verify::parse_verify_and_replay_protect(
            wormhole_state,
            &pool_state.registered_emitters,
            &mut pool_state.consumed_vaas,
            vaa,
            clock,
            ctx
        );
        let payload = vaa::take_payload(vaa);

        let (source_chain_id, nonce, pool_address, receiver, amount, _call_type) =
            pool_codec::decode_withdraw_payload(payload);
        dola_pool::withdraw(
            pool,
            receiver,
            amount,
            pool_address,
            ctx
        );

        emit(PoolWithdrawEvent {
            nonce,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&pool_address),
            pool_address: dola_address::get_dola_address(&pool_address),
            receiver: dola_address::get_dola_address(&receiver),
            amount
        })
    }

    /// === Internal Functions ===

    fun check_relayer(pool_state: &mut PoolState, ctx: &mut TxContext) {
        assert!(
            dynamic_field::exists_with_type<Relayer, vector<address>>(&mut pool_state.id, Relayer {}),
            ERELAYER_NOT_INIT
        );
        let relayers = dynamic_field::borrow<Relayer, vector<address>>(&mut pool_state.id, Relayer {});
        assert!(vector::contains(relayers, &tx_context::sender(ctx)), ENOT_RELAYER);
    }

    fun get_one_relayer(pool_state: &mut PoolState, nonce: u64): address {
        assert!(
            dynamic_field::exists_with_type<Relayer, vector<address>>(&mut pool_state.id, Relayer {}),
            ERELAYER_NOT_INIT
        );
        let relayers = dynamic_field::borrow<Relayer, vector<address>>(&mut pool_state.id, Relayer {});
        let length = vector::length(relayers);
        let index = nonce % length;
        *vector::borrow(relayers, index)
    }
}
