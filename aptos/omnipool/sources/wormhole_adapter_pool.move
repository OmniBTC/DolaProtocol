// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Wormhole bridge adapter, this module is responsible for adapting wormhole to transmit messages across chains
/// for the Sui single currency pool (distinct from the wormhole adapter core). The main purposes of this module are:
/// 1) Receive AppPalod from the application portal, use single currency pool encoding, and transmit messages;
/// 2) Receive withdrawal messages from bridge core for withdrawal
module omnipool::wormhole_adapter_pool {

    use aptos_std::table::{Self, Table};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::Coin;
    use aptos_framework::event::{Self, EventHandle};

    use dola_types::dola_address::{Self, DolaAddress};
    use omnipool::codec_pool;
    use omnipool::single_pool;
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::wormhole;
    use dola_types::dola_contract::{Self, DolaContract};
    use wormhole::set::Set;
    use std::signer;
    use wormhole::set;

    const SEED: vector<u8> = b"Dola Wormhole Adapter Pool";

    /// Errors

    const EINVALIE_DOLA_CONTRACT: u64 = 0;

    const EINVALIE_DOLA_CHAIN: u64 = 1;

    const EINVLIAD_SENDER: u64 = 2;

    const EHAS_INIT: u64 = 3;

    const EINVALID_CALL_TYPE: u64 = 4;

    const ENOT_INIT: u64 = 6;

    const EINVALID_ADMIN: u64 = 7;

    /// `wormhole_bridge_adapter` adapts to wormhole, enabling cross-chain messaging.
    /// For VAA data, the following validations are required.
    /// For wormhole official library: 1) verify the signature.
    /// For wormhole_bridge_adapter itself: 1) make sure it comes from the correct (emitter_chain, wormhole_emitter_address) by
    /// VAA; 2) make sure the data has not been processed by VAA hash;
    struct PoolState has key {
        resource_signer_cap: SignerCapability,
        /// Used to represent the contract address of this module in the Dola protocol
        dola_contract: DolaContract,
        // Move does not have a contract address, Wormhole uses the emitter
        // in EmitterCapability to represent the send address of this contract
        wormhole_emitter: EmitterCapability,
        // Used to verify that the VAA has been processed
        consumed_vaas: Set<vector<u8>>,
        // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
        registered_emitters: Table<u16, ExternalAddress>,
        pool_withdraw_handle: EventHandle<PoolWithdrawEvent>,
        // todo! Delete after wormhole running
        cache_vaas: Table<u64, vector<u8>>,
        nonce: u64
    }

    /// Events

    /// Event for pool withdraw
    struct PoolWithdrawEvent has drop, store {
        nonce: u64,
        source_chain_id: u16,
        dst_chain_id: u16,
        pool_address: vector<u8>,
        receiver: vector<u8>,
        amount: u64
    }

    /// todo! Delete after wormhole running
    struct VaaReciveWithdrawEvent has key, copy, drop {
        pool_address: DolaAddress,
        user_address: DolaAddress,
        amount: u64
    }

    /// todo! Delete after wormhole running
    struct VaaEvent has key, copy, drop {
        vaa: vector<u8>,
        nonce: u64
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @omnipool
    }

    public fun ensure_init(): bool {
        exists<PoolState>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@omnipool, SEED)
    }

    fun get_resouce_signer(): signer acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let dola_contract_registry = borrow_global<PoolState>(get_resource_address());
        account::create_signer_with_capability(&dola_contract_registry.resource_signer_cap)
    }

    /// Initialize for remote bridge and single pool
    public entry fun init(
        sender: &signer,
        sui_wormhole_chain: u16, // Represents the wormhole chain id of the wormhole adpter core on Sui
        sui_wormhole_address: vector<u8>, // Represents the wormhole contract address of the wormhole adpter core on Sui
    ) {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        assert!(!ensure_init(), ENOT_INIT);

        let wormhole_emitter = wormhole::register_emitter();
        let (resource_signer, resource_signer_cap) = account::create_resource_account(sender, SEED);
        let pool_state = PoolState {
            resource_signer_cap,
            dola_contract: dola_contract::create_dola_contract(),
            wormhole_emitter,
            consumed_vaas: set::new<vector<u8>>(),
            registered_emitters: table::new(),
            pool_withdraw_handle: account::new_event_handle(&resource_signer),
            cache_vaas: table::new(),
            nonce: 0
        };
        table::add(
            &mut pool_state.registered_emitters,
            sui_wormhole_chain,
            external_address::from_bytes(sui_wormhole_address)
        );

        move_to(&resource_signer, pool_state);
    }

    /// Call by governance

    /// Register pool owner by governance
    public fun register_owner(
        vaa: vector<u8>,
        new_owner_emitter: &DolaContract
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // let vaa = wormhole_adapter_verify::parse_verify_and_replay_protect(
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        // );
        let (dola_chain_id, dola_contract, call_type) = codec_pool::decode_manage_pool_payload(vaa);
        assert!(call_type == codec_pool::get_register_owner_type(), EINVALID_CALL_TYPE);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        assert!(dola_contract == dola_contract::get_dola_contract(new_owner_emitter), EINVALIE_DOLA_CONTRACT);
        single_pool::register_owner(&pool_state.dola_contract, new_owner_emitter);
    }

    /// Register pool spender by governance
    public fun register_spender(
        vaa: vector<u8>,
        spend_emitter: &DolaContract
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // let vaa = wormhole_adapter_verify::parse_verify_and_replay_protect(
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        // );
        let (dola_chain_id, dola_contract, call_type) = codec_pool::decode_manage_pool_payload(vaa);
        assert!(call_type == codec_pool::get_register_spender_type(), EINVALID_CALL_TYPE);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        assert!(dola_contract == dola_contract::get_dola_contract(spend_emitter), EINVALIE_DOLA_CONTRACT);
        single_pool::register_spender(&pool_state.dola_contract, spend_emitter);
    }

    /// Delete pool owner by governance
    public fun delete_owner(
        vaa: vector<u8>
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // let vaa = wormhole_adapter_verify::parse_verify_and_replay_protect(
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        // );
        let (dola_chain_id, dola_contract, call_type) = codec_pool::decode_manage_pool_payload(vaa);
        assert!(call_type == codec_pool::get_delete_owner_type(), EINVALID_CALL_TYPE);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        single_pool::delete_owner(&pool_state.dola_contract, dola_contract);
    }

    /// Delete pool spender by governance
    public fun delete_spender(
        vaa: vector<u8>
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // let vaa = wormhole_adapter_verify::parse_verify_and_replay_protect(
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        // );
        let (dola_chain_id, dola_contract, call_type) = codec_pool::decode_manage_pool_payload(vaa);
        assert!(call_type == codec_pool::get_delete_spender_type(), EINVALID_CALL_TYPE);
        assert!(dola_chain_id == dola_address::get_native_dola_chain_id(), EINVALIE_DOLA_CHAIN);
        single_pool::delete_owner(&pool_state.dola_contract, dola_contract);
    }

    /// Call by application

    /// Send deposit by application
    public fun send_deposit<CoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        let msg = single_pool::deposit<CoinType>(
            sender,
            deposit_coin,
            app_id,
            app_payload,
        );

        wormhole::publish_message(&mut pool_state.wormhole_emitter, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    /// Send message that do not involve incoming or outgoing funds by application
    public fun send_message(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        app_id: u16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        let msg = single_pool::send_message(
            sender,
            app_id,
            app_payload,
        );
        wormhole::publish_message(&mut pool_state.wormhole_emitter, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    /// Receive withdraw
    public entry fun receive_withdraw<CoinType>(
        vaa: vector<u8>,
    ) acquires PoolState {
        assert!(ensure_init(), ENOT_INIT);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // let vaa = wormhole_adapter_verify::parse_verify_and_replay_protect(
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        // );
        let (source_chain_id, nonce, pool_address, receiver, amount, _call_type) =
            codec_pool::decode_withdraw_payload(vaa);
        single_pool::withdraw<CoinType>(
            &pool_state.dola_contract,
            receiver,
            amount,
            pool_address,
        );
        // myvaa::destroy(vaa);

        event::emit_event(&mut pool_state.pool_withdraw_handle, PoolWithdrawEvent {
            nonce,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&pool_address),
            pool_address: dola_address::get_dola_address(&pool_address),
            receiver: dola_address::get_dola_address(&receiver),
            amount
        })
    }

    public entry fun read_vaa(sender: &signer, index: u64) acquires PoolState {
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        if (index == 0) {
            index = pool_state.nonce;
        };
        move_to(sender, VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index),
            nonce: index
        });
    }

    public entry fun decode_withdraw_payload(sender: &signer, vaa: vector<u8>) {
        let (_, _, pool_address, user_address, amount, _) =
            codec_pool::decode_withdraw_payload(vaa);
        move_to(sender, VaaReciveWithdrawEvent {
            pool_address,
            user_address,
            amount
        })
    }
}
