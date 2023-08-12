// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::lending_core_wormhole_adapter {
    use std::vector;

    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::event;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;

    use dola_protocol::dola_address::{Self, DolaAddress};
    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage::{Self as storage, Storage};
    use dola_protocol::lending_logic;
    use dola_protocol::oracle::PriceOracle;
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::wormhole_adapter_core::{Self, CoreState};
    use wormhole::state::State as WormholeState;

    /// Errors
    const ENOT_ENOUGH_LIQUIDITY: u64 = 0;

    const EINVALID_CALL_TYPE: u64 = 1;

    const ENOT_FIND_POOL: u64 = 2;

    /// Events

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

    /// Relay Event
    struct RelayEvent has drop, copy {
        // Wormhole vaa sequence
        sequence: u64,
        // Source chain id
        source_chain_id: u16,
        // Source chain transaction nonce
        source_chain_nonce: u64,
        // Withdraw pool
        dst_pool: DolaAddress,
        // Confirm that nonce is in the pool or core
        call_type: u8
    }

    /// === Entry Functions ===

    public entry fun supply(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (pool, user, amount, app_payload) = wormhole_adapter_core::receive_deposit(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            clock,
            ctx
        );
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        lending_logic::execute_supply(
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
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (user, app_payload) = wormhole_adapter_core::receive_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
            ctx
        );
        let (source_chain_id, nonce, amount, pool, receiver, call_type) = lending_codec::decode_withdraw_payload(
            app_payload
        );
        assert!(call_type == lending_codec::get_withdraw_type(), EINVALID_CALL_TYPE);
        let amount = (amount as u256);
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        let dst_pool = pool;

        // If the withdrawal exceeds the user's balance, use the maximum withdrawal
        let actual_amount = lending_logic::execute_withdraw(
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

        let sequence = wormhole_adapter_core::send_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            actual_amount,
            wormhole_message_fee,
            clock,
            ctx
        );

        event::emit(RelayEvent {
            sequence,
            dst_pool,
            source_chain_id,
            source_chain_nonce: nonce,
            call_type
        });

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
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (user, app_payload) = wormhole_adapter_core::receive_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
            ctx
        );
        let (source_chain_id, nonce, amount, pool, receiver, call_type) = lending_codec::decode_withdraw_payload(
            app_payload
        );
        assert!(call_type == lending_codec::get_borrow_type(), EINVALID_CALL_TYPE);
        let amount = (amount as u256);
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        let dst_pool = pool;

        lending_logic::execute_borrow(
            pool_manager_info,
            storage,
            oracle,
            clock,
            dola_user_id,
            dola_pool_id,
            amount
        );

        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= amount, ENOT_ENOUGH_LIQUIDITY);

        let sequence = wormhole_adapter_core::send_withdraw(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            amount,
            wormhole_message_fee,
            clock,
            ctx
        );

        event::emit(RelayEvent {
            sequence,
            dst_pool,
            source_chain_id,
            source_chain_nonce: nonce,
            call_type
        });

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
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (pool, user, amount, app_payload) = wormhole_adapter_core::receive_deposit(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            clock,
            ctx
        );
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user);
        lending_logic::execute_repay(
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
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
            ctx
        );
        let (source_chain_id, nonce, repay_pool_id, liquidate_user_id, liquidate_pool_id, call_type) = lending_codec::decode_liquidate_payload_v2(
            app_payload
        );

        let liquidator = user_manager::get_dola_user_id(user_manager_info, sender);

        lending_logic::execute_liquidate(
            pool_manager_info,
            storage,
            oracle,
            clock,
            liquidator,
            liquidate_user_id,
            liquidate_pool_id,
            repay_pool_id,
        );

        event::emit(LendingCoreEvent {
            nonce,
            sender_user_id: liquidator,
            source_chain_id,
            dst_chain_id: dola_address::get_dola_chain_id(&sender),
            dola_pool_id: liquidate_pool_id,
            receiver: dola_address::get_dola_address(&sender),
            amount: 0,
            liquidate_user_id,
            call_type
        })
    }

    public entry fun as_collateral(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        // Verify that a message is valid using the wormhole
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
            ctx
        );
        let (dola_pool_ids, call_type) = lending_codec::decode_manage_collateral_payload(app_payload);
        assert!(call_type == lending_codec::get_as_colleteral_type(), EINVALID_CALL_TYPE);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            lending_logic::as_collateral(
                pool_manager_info,
                storage,
                oracle,
                clock,
                dola_user_id,
                *dola_pool_id
            );
            i = i + 1;
        };
    }

    public entry fun cancel_as_collateral(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        // Verify that a message is valid using the wormhole
        let (sender, app_payload) = wormhole_adapter_core::receive_message(
            wormhole_state,
            core_state,
            storage::get_app_cap(storage),
            vaa,
            clock,
            ctx
        );
        let (dola_pool_ids, call_type) = lending_codec::decode_manage_collateral_payload(app_payload);
        assert!(call_type == lending_codec::get_cancel_as_colleteral_type(), EINVALID_CALL_TYPE);

        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            lending_logic::cancel_as_collateral(
                pool_manager_info,
                storage,
                oracle,
                clock,
                dola_user_id,
                *dola_pool_id
            );
            i = i + 1;
        };
    }
}
