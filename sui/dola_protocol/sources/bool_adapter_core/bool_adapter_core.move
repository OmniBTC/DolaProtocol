// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Boolnet bridge adapter, this module is responsible for adapting boolnet to pass messages for settlement center
/// applications (such as lending core). The usage of this module are: 1) Update the status of user_manager and
/// pool_manager; 2) Verify message signature, decode PoolPaload, and pass it to the correct application
module dola_protocol::bool_adapter_core {
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::dynamic_object_field;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::table;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context;
    use sui::tx_context::{TxContext, sender};

    use boolamt::anchor::{AnchorCap, GlobalState, enable_path};
    use boolamt::consumer;
    use boolamt::messenger;

    use dola_protocol::app_manager::{Self, AppCap};
    use dola_protocol::dola_address;
    use dola_protocol::dola_address::{DolaAddress, get_dola_chain_id};
    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::pool_codec;
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::remote_gov_codec;
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::bool_adapter_verify::{
        parse_verify_and_replay_protect,
        remapping_opcode,
        client_opcode_add_relayer,
        client_opcode_remove_relayer,
        client_opcode_register_spender,
        client_opcode_delete_spender,
        client_opcode_withdraw
    };


    friend dola_protocol::system_core_bool_adapter;
    friend dola_protocol::lending_core_bool_adapter;

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


    /// `bool_bridge_adapter` adapts to boolnet, enabling cross-chain messaging.
    /// For messsage data, the following validations are required.
    /// For boolamt official library:
    /// 1) verify the signature.
    /// 2) make sure it comes from the correct path(dst_chain_id, dst_anchor)
    /// 3) make sure the data has not been processed by tx_unique_identification;
    /// For bool_bridge_adapter itself:
    /// 1) make sure the caller is from the correct application by app_id from pool payload.
    struct CoreState has key, store {
        id: UID,
        // dola_chain_id(dola config) => dst_chain_id(boolnet config)
        chain_id_map: table::Table<u16, u32>
    }

    /// Move does not have a contract address, boolnet uses the AnchorCap
    /// to represent the send address of this contract
    struct BoolAnchorCap has copy, drop, store {}

    /// Only certain users are allowed to act as Relayer
    struct Relayer has copy, drop, store {}

    /// Events

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
        governance_cap: &GovernanceCap,
        bool_anchor_cap: AnchorCap,
        init_relayer: address,
        ctx: &mut TxContext
    ) {
        let core_state = CoreState {
            id: object::new(ctx),
            chain_id_map: table::new(ctx)
        };

        dynamic_object_field::add<BoolAnchorCap, AnchorCap>(
            &mut core_state.id,
            BoolAnchorCap {},
            bool_anchor_cap
        );

        add_relayer(
            governance_cap,
            &mut core_state,
            init_relayer
        );

        transfer::public_share_object(core_state);
    }

    /// Call by governance

    public fun set_anchor_cap(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        bool_anchor_cap: AnchorCap
    ) {
        dynamic_object_field::add<BoolAnchorCap, AnchorCap>(
            &mut core_state.id,
            BoolAnchorCap {},
            bool_anchor_cap
        );
    }

    public fun release_anchor_cap(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        receiver: address
    ) {
        let bool_anchor_cap = dynamic_object_field::remove<BoolAnchorCap, AnchorCap>(
            &mut core_state.id,
            BoolAnchorCap {}
        );

        transfer::public_transfer(bool_anchor_cap, receiver)
    }

    /// Register path on boolamt contract
    public fun register_path(
        _: &GovernanceCap,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dst_chain_id: u32,
        dst_anchor: address,
        bool_global_state: &mut GlobalState,
    ) {
        enable_path(
            dst_chain_id,
            dst_anchor,
            get_anchor_cap(&core_state.id),
            bool_global_state
        );

        table::add(&mut core_state.chain_id_map, dola_chain_id, dst_chain_id)
    }

    /// Register spender for remote bridge through governance
    public fun remote_register_spender(
        _: &GovernanceCap,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        bool_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let payload = pool_codec::encode_manage_pool_payload(
            dola_chain_id,
            dola_contract,
            pool_codec::get_register_spender_type()
        );

        remapping_opcode(&mut payload, client_opcode_register_spender());

        let dst_chain_id = table::borrow<u16, u32>(
            &core_state.chain_id_map,
            dola_chain_id
        );

        send_to_bool(
            *dst_chain_id,
            payload,
            bool_message_fee,
            get_anchor_cap(&core_state.id),
            bool_state,
            ctx
        );

        event::emit(RegisterSpender { dola_chain_id, dola_contract });
    }

    /// Delete spender for remote bridge through governance
    public fun remote_delete_spender(
        _: &GovernanceCap,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        bool_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let payload = pool_codec::encode_manage_pool_payload(
            dola_chain_id,
            dola_contract,
            pool_codec::get_delete_spender_type()
        );

        remapping_opcode(&mut payload, client_opcode_delete_spender());

        let dst_chain_id = table::borrow<u16, u32>(
            &core_state.chain_id_map,
            dola_chain_id
        );

        send_to_bool(
            *dst_chain_id,
            payload,
            bool_message_fee,
            get_anchor_cap(&core_state.id),
            bool_state,
            ctx
        );

        event::emit(DeleteSpender { dola_chain_id, dola_contract });
    }

    public fun remote_add_relayer(
        _: &GovernanceCap,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        relayer: vector<u8>,
        bool_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let payload = remote_gov_codec::encode_relayer_payload(
            dola_address::create_dola_address(dola_chain_id, relayer),
            remote_gov_codec::get_add_relayer_opcode()
        );

        remapping_opcode(&mut payload, client_opcode_add_relayer());

        let dst_chain_id = table::borrow<u16, u32>(
            &core_state.chain_id_map,
            dola_chain_id
        );

        send_to_bool(
            *dst_chain_id,
            payload,
            bool_message_fee,
            get_anchor_cap(&core_state.id),
            bool_state,
            ctx
        );
    }

    public fun remote_remove_relayer(
        _: &GovernanceCap,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        relayer: vector<u8>,
        bool_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let payload = remote_gov_codec::encode_relayer_payload(
            dola_address::create_dola_address(dola_chain_id, relayer),
            remote_gov_codec::get_remove_relayer_opcode()
        );

        remapping_opcode(&mut payload, client_opcode_remove_relayer());

        let dst_chain_id = table::borrow<u16, u32>(
            &core_state.chain_id_map,
            dola_chain_id
        );

        send_to_bool(
            *dst_chain_id,
            payload,
            bool_message_fee,
            get_anchor_cap(&core_state.id),
            bool_state,
            ctx
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

    public fun get_bool_chain_id(
        core_state: &CoreState,
        dola_chain_id: u16
    ): u32 {
        let bool_chain_id = table::borrow<u16, u32>(
            &core_state.chain_id_map,
            dola_chain_id
        );

        return *bool_chain_id
    }

    /// === Friend Functions ===

    /// Receive message without funding
    public(friend) fun receive_message(
        core_state: &mut CoreState,
        bool_state: &mut GlobalState,
        message_raw: vector<u8>,
        signature: vector<u8>,
        app_cap: &AppCap,
        ctx: &mut TxContext
    ): (DolaAddress, vector<u8>) {
        check_relayer(core_state, ctx);

        let payload_without_opcode = parse_verify_and_replay_protect(
            message_raw,
            signature,
            get_anchor_cap(&core_state.id),
            bool_state
        );

        let (user_address, app_id, _, app_payload) =
            pool_codec::decode_send_message_payload(payload_without_opcode);

        // Ensure that vaa is delivered to the correct application
        assert!(app_manager::get_app_id(app_cap) == app_id, EINVALID_APP);
        (user_address, app_payload)
    }

    /// Receive deposit on sui network
    public(friend) fun receive_deposit(
        core_state: &mut CoreState,
        bool_state: &mut GlobalState,
        message_raw: vector<u8>,
        signature: vector<u8>,
        app_cap: &AppCap,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        ctx: &mut TxContext
    ): (DolaAddress, DolaAddress, u256, vector<u8>) {
        check_relayer(core_state, ctx);

        let payload_without_opcode = parse_verify_and_replay_protect(
            message_raw,
            signature,
            get_anchor_cap(&core_state.id),
            bool_state
        );

        let (pool_address, user_address, amount, app_id, _, app_payload) =
            pool_codec::decode_deposit_payload(payload_without_opcode);

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

        (pool_address, user_address, actual_amount, app_payload)
    }

    /// Receive withdraw on sui network
    public(friend) fun receive_withdraw(
        core_state: &mut CoreState,
        bool_state: &mut GlobalState,
        message_raw: vector<u8>,
        signature: vector<u8>,
        app_cap: &AppCap,
        ctx: &mut TxContext
    ): (DolaAddress, vector<u8>) {
        check_relayer(core_state, ctx);

        let payload_without_opcode = parse_verify_and_replay_protect(
            message_raw,
            signature,
            get_anchor_cap(&core_state.id),
            bool_state
        );

        let (user_address, app_id, _, app_payload) =
            pool_codec::decode_send_message_payload(payload_without_opcode);

        // Ensure that vaa is delivered to the correct application
        assert!(app_manager::get_app_id(app_cap) == app_id, EINVALID_APP);

        (user_address, app_payload)
    }

    /// Send withdraw on sui network
    public(friend) fun send_withdraw(
        core_state: &mut CoreState,
        bool_state: &mut GlobalState,
        app_cap: &AppCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_address: DolaAddress,
        user_address: DolaAddress,
        source_chain_id: u16,
        nonce: u64,
        amount: u256,
        bool_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    ): u64 {
        check_relayer(core_state, ctx);
        let (actual_amount, _) = pool_manager::remove_liquidity(
            pool_manager_info,
            pool_address,
            app_manager::get_app_id(app_cap),
            amount
        );
        let payload = pool_codec::encode_withdraw_payload(
            source_chain_id,
            nonce,
            pool_address,
            user_address,
            (actual_amount as u64)
        );

        remapping_opcode(&mut payload, client_opcode_withdraw());

        let dst_chain_id = get_bool_chain_id(
            core_state,
            get_dola_chain_id(&pool_address)
        );

        send_to_bool(
            dst_chain_id,
            payload,
            bool_message_fee,
            get_anchor_cap(&core_state.id),
            bool_state,
            ctx
        );

        return 0
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

    fun get_anchor_cap(
        core_state_id: &UID
    ): &AnchorCap {
        let bool_anchor_cap = dynamic_object_field::borrow<BoolAnchorCap, AnchorCap>(
            core_state_id,
            BoolAnchorCap {}
        );

        return bool_anchor_cap
    }

    fun send_to_bool(
        dst_chain_id: u32,
        payload: vector<u8>,
        bool_message_fee: Coin<SUI>,
        anchor_cap: &AnchorCap,
        global_state: &mut GlobalState,
        ctx: &mut TxContext,
    ) {
        let remain_fee = consumer::send_message(
            dst_chain_id,
            messenger::pure_message(),
            // bn_extra_feed not used.
            std::vector::empty(),
            payload,
            bool_message_fee,
            anchor_cap,
            global_state,
            ctx,
        );

        // return remaining fee
        if (coin::value(&remain_fee) == 0) {
            coin::destroy_zero(remain_fee);
        } else {
            transfer::public_transfer(remain_fee, sender(ctx));
        };
    }
}
