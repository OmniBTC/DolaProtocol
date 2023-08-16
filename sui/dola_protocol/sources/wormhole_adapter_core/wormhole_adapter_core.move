// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Wormhole bridge adapter, this module is responsible for adapting wormhole to pass messages for settlement center
/// applications (such as lending core). The usage of this module are: 1) Update the status of user_manager and
/// pool_manager; 2) Verify VAA and  message source, decode PoolPaload, and pass it to the correct application
module dola_protocol::wormhole_adapter_core {
    use std::vector;

    use sui::clock;
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context;
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};

    use dola_protocol::app_manager::{Self, AppCap};
    use dola_protocol::dola_address;
    use dola_protocol::dola_address::DolaAddress;
    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::pool_codec;
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::remote_gov_codec;
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::wormhole_adapter_verify::{Self, Unit};
    use wormhole::bytes32::{Self, Bytes32};
    use wormhole::emitter::{Self, EmitterCap};
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::publish_message;
    use wormhole::state::State;
    use wormhole::vaa;

    friend dola_protocol::system_core_wormhole_adapter;
    friend dola_protocol::lending_core_wormhole_adapter;
    friend dola_protocol::lending_portal;

    /// Errors
    // Bridge is not registered
    const ENOT_REGISTERED_EMITTER: u64 = 0;

    // Bridge has registered
    const EHAS_REGISTERED_EMITTER: u64 = 1;

    // Invalid App
    const EINVALID_APP: u64 = 2;

    const EDUPLICATED_RELAYER: u64 = 3;

    const ENOT_RELAYER: u64 = 4;

    const ERELAYER_NOT_INIT: u64 = 5;

    const ERELAYER_NOT_EXIST: u64 = 6;

    const EVAA_HAS_EXPIRED: u64 = 7;

    const DEFAULT_VAA_EXPIRED_TIME: u64 = 3600;

    /// `wormhole_bridge_adapter` adapts to wormhole, enabling cross-chain messaging.
    /// For VAA data, the following validations are required.
    /// For wormhole official library: 1) verify the signature.
    /// For wormhole_bridge_adapter itself: 1) make sure it comes from the correct (emitter_chain, wormhole_emitter_address) by
    /// VAA; 2) make sure the data has not been processed by VAA hash; 3) make sure the caller is from the correct
    /// application by app_id from pool payload.
    struct CoreState has key, store {
        id: UID,
        // Move does not have a contract address, Wormhole uses the emitter
        // in EmitterCap to represent the send address of this contract
        wormhole_emitter: EmitterCap,
        // Used to verify that the VAA has been processed
        consumed_vaas: object_table::ObjectTable<Bytes32, Unit>,
        // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
        registered_emitters: VecMap<u16, ExternalAddress>,
    }

    /// Only certain users are allowed to act as Relayer
    struct Relayer has copy, drop, store {}

    /// Vaa expired time
    struct VaaExpiredTime has copy, drop, store {}

    /// Events

    /// Event for register bridge
    struct RegisterBridge has copy, drop {
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>
    }

    /// Event for delete bridge
    struct DeleteBridge has copy, drop {
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>
    }

    /// Deprecated
    /// Event for register owner
    struct RegisterOwner has copy, drop {
        dola_chain_id: u16,
        dola_contract: u256
    }

    /// Deprecated
    /// Event for delete owner
    struct DeleteOwner has copy, drop {
        dola_chain_id: u16,
        dola_contract: u256
    }

    /// Event for register spender
    struct RegisterSpender has copy, drop {
        dola_chain_id: u16,
        dola_contract: u256
    }

    /// Event for delete spender
    struct DeleteSpender has copy, drop {
        dola_chain_id: u16,
        dola_contract: u256
    }

    /// Event for add relayer
    struct AddRelayer has drop, copy {
        new_relayer: address
    }

    /// Event for remove relayer
    struct RemoveRelayer has drop, copy {
        removed_relayer: address
    }

    /// === Governance Functions ===

    /// Initializing caps of PoolManager and UserManager through governance
    public fun initialize_cap_with_governance(
        _: &GovernanceCap,
        wormhole_state: &mut State,
        ctx: &mut TxContext
    ) {
        transfer::public_share_object(
            CoreState {
                id: object::new(ctx),
                wormhole_emitter: emitter::new(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty()
            }
        );
    }

    /// Call by governance

    /// Register the remote wormhole adapter pool through governance
    /// Steps for registering a remote bridge:
    /// 1) By governing the call to `initialize_cap_with_governance` of wormhole adapter core
    /// 2) Call to `initialize` of wormhole adapter pool
    /// 3) By governing the call to `register_remote_bridge`
    public fun register_remote_bridge(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>
    ) {
        assert!(!vec_map::contains(&core_state.registered_emitters, &wormhole_emitter_chain), EHAS_REGISTERED_EMITTER);
        vec_map::insert(
            &mut core_state.registered_emitters,
            wormhole_emitter_chain,
            external_address::new(bytes32::new(wormhole_emitter_address))
        );
        event::emit(RegisterBridge { wormhole_emitter_chain, wormhole_emitter_address });
    }

    /// Delete the remote wormhole adapter pool through governance
    public fun delete_remote_bridge(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16
    ) {
        assert!(vec_map::contains(&core_state.registered_emitters, &wormhole_emitter_chain), ENOT_REGISTERED_EMITTER);
        let (_, wormhole_emitter_address) = vec_map::remove(
            &mut core_state.registered_emitters,
            &wormhole_emitter_chain
        );
        event::emit(RegisterBridge {
            wormhole_emitter_chain,
            wormhole_emitter_address: external_address::to_bytes(wormhole_emitter_address)
        });
    }

    /// Deprecated
    /// Register owner for remote bridge through governance
    public fun remote_register_owner(
        _: &GovernanceCap,
        _wormhole_state: &mut State,
        _core_state: &mut CoreState,
        _dola_chain_id: u16,
        _dola_contract: u256,
        _wormhole_message_fee: Coin<SUI>,
        _clock: &Clock,
    ) {
        abort 0
    }

    /// Deprecated
    /// Delete owner for remote bridge through governance
    public fun remote_delete_owner(
        _: &GovernanceCap,
        _wormhole_state: &mut State,
        _core_state: &mut CoreState,
        _dola_chain_id: u16,
        _dola_contract: u256,
        _wormhole_message_fee: Coin<SUI>,
        _clock: &Clock
    ) {
        abort 0
    }

    /// Register spender for remote bridge through governance
    public fun remote_register_spender(
        _: &GovernanceCap,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ) {
        let msg = pool_codec::encode_manage_pool_payload(
            dola_chain_id,
            dola_contract,
            pool_codec::get_register_spender_type()
        );
        let message_ticket = publish_message::prepare_message(
            &mut core_state.wormhole_emitter,
            0,
            msg,
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        );
        event::emit(RegisterSpender { dola_chain_id, dola_contract });
    }

    /// Delete spender for remote bridge through governance
    public fun remote_delete_spender(
        _: &GovernanceCap,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock
    ) {
        let msg = pool_codec::encode_manage_pool_payload(
            dola_chain_id,
            dola_contract,
            pool_codec::get_delete_spender_type()
        );
        let message_ticket = publish_message::prepare_message(
            &mut core_state.wormhole_emitter,
            0,
            msg,
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        );
        event::emit(DeleteSpender { dola_chain_id, dola_contract });
    }

    public fun remote_add_relayer(
        _: &GovernanceCap,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        relayer: vector<u8>,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock
    ) {
        let msg = remote_gov_codec::encode_relayer_payload(
            dola_address::create_dola_address(dola_chain_id, relayer),
            remote_gov_codec::get_add_relayer_opcode()
        );

        let message_ticket = publish_message::prepare_message(
            &mut core_state.wormhole_emitter,
            0,
            msg,
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        );
    }

    public fun remote_remove_relayer(
        _: &GovernanceCap,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        relayer: vector<u8>,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock
    ) {
        let msg = remote_gov_codec::encode_relayer_payload(
            dola_address::create_dola_address(dola_chain_id, relayer),
            remote_gov_codec::get_remove_relayer_opcode()
        );

        let message_ticket = publish_message::prepare_message(
            &mut core_state.wormhole_emitter,
            0,
            msg,
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        );
    }

    public fun add_relayer(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        relayer: address
    ) {
        if (dynamic_field::exists_with_type<Relayer, vector<address>>(&mut core_state.id, Relayer {})) {
            let relayers = dynamic_field::borrow_mut<Relayer, vector<address>>(&mut core_state.id, Relayer {});
            assert!(!vector::contains(relayers, &relayer), EDUPLICATED_RELAYER);
            vector::push_back(relayers, relayer);
        } else {
            dynamic_field::add<Relayer, vector<address>>(&mut core_state.id, Relayer {}, vector[relayer]);
        };
        event::emit(AddRelayer {
            new_relayer: relayer
        });
    }

    public fun remove_relayer(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        relayer: address
    ) {
        assert!(
            dynamic_field::exists_with_type<Relayer, vector<address>>(&mut core_state.id, Relayer {}),
            ERELAYER_NOT_INIT
        );
        let relayers = dynamic_field::borrow_mut<Relayer, vector<address>>(&mut core_state.id, Relayer {});
        assert!(vector::contains(relayers, &relayer), ERELAYER_NOT_EXIST);
        let (_, index) = vector::index_of(relayers, &relayer);
        vector::remove(relayers, index);
        event::emit(RemoveRelayer {
            removed_relayer: relayer
        });
    }

    public fun set_vaa_expired_time(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        vaa_expired_time: u64
    ) {
        if (dynamic_field::exists_with_type<VaaExpiredTime, u64>(&mut core_state.id, VaaExpiredTime {})) {
            dynamic_field::remove<VaaExpiredTime, u64>(&mut core_state.id, VaaExpiredTime {});
        };
        dynamic_field::add<VaaExpiredTime, u64>(&mut core_state.id, VaaExpiredTime {}, vaa_expired_time)
    }

    /// === Friend Functions ===

    /// Receive message without funding
    public(friend) fun receive_message(
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (DolaAddress, vector<u8>) {
        check_relayer(core_state, ctx);
        let msg = wormhole_adapter_verify::parse_verify_and_replay_protect(
            wormhole_state,
            &core_state.registered_emitters,
            &mut core_state.consumed_vaas,
            vaa,
            clock,
            ctx,
        );
        let payload = vaa::take_payload(msg);

        let (user_address, app_id, _, app_payload) =
            pool_codec::decode_send_message_payload(payload);

        // Ensure that vaa is delivered to the correct application
        assert!(app_manager::get_app_id(app_cap) == app_id, EINVALID_APP);
        (user_address, app_payload)
    }

    /// Receive deposit on sui network
    public(friend) fun receive_deposit(
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        clock: &Clock,
        ctx: &mut TxContext
    ): (DolaAddress, DolaAddress, u256, vector<u8>) {
        check_relayer(core_state, ctx);
        let msg = wormhole_adapter_verify::parse_verify_and_replay_protect(
            wormhole_state,
            &core_state.registered_emitters,
            &mut core_state.consumed_vaas,
            vaa,
            clock,
            ctx,
        );
        let payload = vaa::take_payload(msg);

        let (pool_address, user_address, amount, app_id, _, app_payload) =
            pool_codec::decode_deposit_payload(payload);

        // Ensure that vaa is delivered to the correct application
        assert!(app_manager::get_app_id(app_cap) == app_id, EINVALID_APP);

        let (actual_amount, _) = pool_manager::add_liquidity(
            pool_manager_info,
            pool_address,
            app_manager::get_app_id(app_cap),
            (amount as u256),
        );

        if (!user_manager::is_dola_user(user_manager_info, user_address)) {
            user_manager::register_dola_user_id(user_manager_info, user_address);
        };

        // myvaa::destroy(vaa);
        (pool_address, user_address, actual_amount, app_payload)
    }

    /// Receive withdraw on sui network
    public(friend) fun receive_withdraw(
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (DolaAddress, vector<u8>) {
        check_relayer(core_state, ctx);
        let msg = wormhole_adapter_verify::parse_verify_and_replay_protect(
            wormhole_state,
            &core_state.registered_emitters,
            &mut core_state.consumed_vaas,
            vaa,
            clock,
            ctx,
        );
        let vaa_timestamp = vaa::timestamp(&msg);
        check_vaa_expired_time(core_state, (vaa_timestamp as u64), clock);

        let payload = vaa::take_payload(msg);

        let (user_address, app_id, _, app_payload) =
            pool_codec::decode_send_message_payload(payload);

        // Ensure that vaa is delivered to the correct application
        assert!(app_manager::get_app_id(app_cap) == app_id, EINVALID_APP);

        // myvaa::destroy(vaa);
        (user_address, app_payload)
    }

    /// Send withdraw on sui network
    public(friend) fun send_withdraw(
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        app_cap: &AppCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_address: DolaAddress,
        user_address: DolaAddress,
        source_chain_id: u16,
        nonce: u64,
        amount: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        check_relayer(core_state, ctx);
        let (actual_amount, _) = pool_manager::remove_liquidity(
            pool_manager_info,
            pool_address,
            app_manager::get_app_id(app_cap),
            amount
        );
        let msg = pool_codec::encode_withdraw_payload(
            source_chain_id,
            nonce,
            pool_address,
            user_address,
            (actual_amount as u64)
        );
        let message_ticket = publish_message::prepare_message(
            &mut core_state.wormhole_emitter,
            0,
            msg,
        );

        publish_message::publish_message(
            wormhole_state,
            wormhole_message_fee,
            message_ticket,
            clock
        )
    }

    /// === Internal Functions ===

    fun check_relayer(core_state: &mut CoreState, ctx: &mut TxContext) {
        assert!(
            dynamic_field::exists_with_type<Relayer, vector<address>>(&mut core_state.id, Relayer {}),
            ERELAYER_NOT_INIT
        );
        let relayers = dynamic_field::borrow<Relayer, vector<address>>(&mut core_state.id, Relayer {});
        assert!(vector::contains(relayers, &tx_context::sender(ctx)), ENOT_RELAYER);
    }

    fun check_vaa_expired_time(core_state: &mut CoreState, vaa_timestamp: u64, clock: &Clock) {
        let vaa_expired_time = DEFAULT_VAA_EXPIRED_TIME;
        if (dynamic_field::exists_with_type<VaaExpiredTime, u64>(&mut core_state.id, VaaExpiredTime {})) {
            vaa_expired_time = *dynamic_field::borrow<VaaExpiredTime, u64>(&mut core_state.id, VaaExpiredTime {});
        };

        assert!(vaa_timestamp + vaa_expired_time < clock::timestamp_ms(clock) / 1000, EVAA_HAS_EXPIRED);
    }
}
