// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module lending_core::wormhole_adapter {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::dola_address;
    use lending_core::lending_codec;
    use lending_core::logic;
    use lending_core::storage::{Self, StorageCap, Storage};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::event;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State as WormholeState;
    use wormhole_adapter_core::wormhole_adapter_core::{Self, CoreState};

    /// Errors
    const EMUST_NONE: u64 = 0;

    const EMUST_SOME: u64 = 1;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 2;

    const EINVALID_LENGTH: u64 = 3;

    const EINVALID_CALL_TYPE: u64 = 4;

    struct WormholeAdapter has key {
        id: UID,
        storage_cap: Option<StorageCap>
    }

    struct LendingCoreEvent has drop, copy {
        nonce: u64,
        sender_user_id: u64,
        source_chain_id: u16,
        dst_chain_id: u16,
        dola_pool_id: u16,
        receiver: vector<u8>,
        amount: u256,
        liquidate_user_id: u64,
        call_type: u8
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(WormholeAdapter {
            id: object::new(ctx),
            storage_cap: option::none()
        })
    }

    public fun transfer_storage_cap(
        wormhole_adapter: &mut WormholeAdapter,
        storage_cap: StorageCap
    ) {
        assert!(option::is_none(&wormhole_adapter.storage_cap), EMUST_NONE);
        option::fill(&mut wormhole_adapter.storage_cap, storage_cap);
    }

    fun get_storage_cap(wormhole_adapter: &WormholeAdapter): &StorageCap {
        assert!(option::is_some(&wormhole_adapter.storage_cap), EMUST_SOME);
        option::borrow(&wormhole_adapter.storage_cap)
    }

    public entry fun supply(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (pool, user, amount, app_payload) = wormhole_adapter_core::receive_deposit(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            ctx
        );
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        logic::execute_supply(
            cap,
            pool_manager_info,
            storage,
            oracle,
            clock,
            dola_user_id,
            dola_pool_id,
            amount
        );
        // emit event
        let (source_chain_id, nonce, receiver, call_type) = lending_codec::decode_deposit_payload(app_payload);
        assert!(call_type == lending_codec::get_supply_type(), EINVALID_CALL_TYPE);
        event::emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address::get_dola_address(&receiver),
            amount,
            liquidate_user_id: 0,
            call_type
        })
    }

    public entry fun withdraw(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (user, app_payload) = wormhole_adapter_core::receive_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let (source_chain_id, nonce, amount, pool, receiver, call_type) = lending_codec::decode_withdraw_payload(
            app_payload
        );
        assert!(call_type == lending_codec::get_withdraw_type(), EINVALID_CALL_TYPE);
        let amount = (amount as u256);
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        let dst_chain = dola_address::get_dola_chain_id(&receiver);
        let dst_pool = pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // If the withdrawal exceeds the user's balance, use the maximum withdrawal
        let actual_amount = logic::execute_withdraw(
            cap,
            pool_manager_info,
            storage,
            oracle,
            clock,
            dola_user_id,
            dola_pool_id,
            amount,
        );

        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= actual_amount, ENOT_ENOUGH_LIQUIDITY);

        wormhole_adapter_core::send_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            actual_amount,
            wormhole_message_fee
        );

        event::emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address::get_dola_address(&receiver),
            amount: actual_amount,
            liquidate_user_id: 0,
            call_type
        })
    }

    public entry fun borrow(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (user, app_payload) = wormhole_adapter_core::receive_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let (source_chain_id, nonce, amount, pool, receiver, call_type) = lending_codec::decode_withdraw_payload(
            app_payload
        );
        assert!(call_type == lending_codec::get_borrow_type(), EINVALID_CALL_TYPE);
        let amount = (amount as u256);

        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);

        let dst_chain = dola_address::get_dola_chain_id(&receiver);
        let dst_pool = pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= amount, ENOT_ENOUGH_LIQUIDITY);

        logic::execute_borrow(cap, pool_manager_info, storage, oracle, clock, dola_user_id, dola_pool_id, amount);
        wormhole_adapter_core::send_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            amount,
            wormhole_message_fee
        );

        event::emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address::get_dola_address(&receiver),
            amount,
            liquidate_user_id: 0,
            call_type
        })
    }

    public entry fun repay(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (pool, user, amount, app_payload) = wormhole_adapter_core::receive_deposit(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            ctx
        );
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        logic::execute_repay(cap, pool_manager_info, storage, oracle, clock, dola_user_id, dola_pool_id, amount);

        // emit event
        let (source_chain_id, nonce, receiver, call_type) = lending_codec::decode_deposit_payload(app_payload);
        assert!(call_type == lending_codec::get_repay_type(), EINVALID_CALL_TYPE);
        event::emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address::get_dola_address(&receiver),
            amount,
            liquidate_user_id: 0,
            call_type
        })
    }

    public entry fun liquidate(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (deposit_pool, deposit_user, deposit_amount, app_payload) = wormhole_adapter_core::receive_deposit(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            ctx
        );
        let (source_chain_id, nonce, withdraw_pool, liquidate_user_id, call_type) = lending_codec::decode_liquidate_payload(
            app_payload
        );

        let liquidator = user_manager::get_dola_user_id(user_manager_info, deposit_user);
        let deposit_dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, deposit_pool);
        let withdraw_dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, withdraw_pool);
        logic::execute_supply(
            cap,
            pool_manager_info,
            storage,
            oracle,
            clock,
            liquidator,
            deposit_dola_pool_id,
            deposit_amount
        );

        logic::execute_liquidate(
            cap,
            pool_manager_info,
            storage,
            oracle,
            clock,
            liquidator,
            liquidate_user_id,
            withdraw_dola_pool_id,
            deposit_dola_pool_id,
        );

        event::emit(LendingCoreEvent {
            nonce,
            sender_user_id: liquidator,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&deposit_user),
            dola_pool_id: withdraw_dola_pool_id,
            receiver: dola_address::get_dola_address(&deposit_user),
            amount: deposit_amount,
            liquidate_user_id,
            call_type
        })
    }

    public entry fun as_collateral(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        // Verify that a message is valid using the wormhole
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa
        );
        let (dola_pool_ids, call_type) = lending_codec::decode_manage_collateral_payload(app_payload);
        assert!(call_type == lending_codec::get_as_colleteral_type(), EINVALID_CALL_TYPE);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            logic::as_collateral(cap, pool_manager_info, storage, oracle, clock, dola_user_id, *dola_pool_id);
            i = i + 1;
        };
    }

    public entry fun cancel_as_collateral(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        // Verify that a message is valid using the wormhole
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(cap, storage),
            vaa
        );
        let (dola_pool_ids, call_type) = lending_codec::decode_manage_collateral_payload(app_payload);
        assert!(call_type == lending_codec::get_cancel_as_colleteral_type(), EINVALID_CALL_TYPE);

        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            logic::cancel_as_collateral(cap, pool_manager_info, storage, oracle, clock, dola_user_id, *dola_pool_id);
            i = i + 1;
        };
    }
}
