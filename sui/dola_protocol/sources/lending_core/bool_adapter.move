// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::lending_core_bool_adapter {
    use std::vector;

    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::event;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;

    use boolamt::anchor::{GlobalState, get_fee_collector};
    use boolamt::fee_collector;
    use boolamt::messenger;

    use dola_protocol::dola_address::{Self, DolaAddress};
    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage::{Self as storage, Storage};
    use dola_protocol::lending_logic;
    use dola_protocol::pool_codec;
    use dola_protocol::oracle::PriceOracle;
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::bool_adapter_core::{Self, CoreState, get_bool_chain_id};
    use dola_protocol::bool_adapter_verify::{
        remapping_opcode,
        check_server_opcode,
        client_opcode_withdraw,
        server_opcode_lending_supply,
        server_opcode_lending_withdraw,
        server_opcode_lending_borrow,
        server_opcode_lending_repay,
        server_opcode_lending_liquidate,
        server_opcode_lending_collateral,
        server_opcode_lending_cancle_collateral
    };


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

    /// === Public Functions ===

    public fun calc_withdrow_bool_message_fee(
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        message_raw: vector<u8>
    ): u64 {
        let message = messenger::message_from_bcs(&message_raw);
        let payload_with_opcode = messenger::payload(&message);
        let opcode = vector::pop_back(&mut payload_with_opcode);
        let payload = payload_with_opcode;
        
        if (opcode != server_opcode_lending_withdraw() && 
            opcode != server_opcode_lending_borrow()){
            return 0
        };

        let (
            user_address, 
            _app_id, 
            _, 
            app_payload
        ) = 
            pool_codec::decode_send_message_payload(payload);

        let (
            source_chain_id, 
            nonce, 
            amount, 
            pool_address, 
            _receiver, 
            call_type
        ) = 
            lending_codec::decode_withdraw_payload(app_payload);

        if (call_type != lending_codec::get_withdraw_type() && 
            call_type != lending_codec::get_borrow_type()) {
            return 0
        };

        let new_payload = pool_codec::encode_withdraw_payload(
            source_chain_id,
            nonce,
            pool_address,
            user_address,
            amount
        );
        remapping_opcode(&mut new_payload, client_opcode_withdraw());

        let new_payload_length = vector::length(&new_payload);

        let dst_chain_id = get_bool_chain_id(core_state, source_chain_id);

        let fee_collector = get_fee_collector(bool_global);
        let fee = fee_collector::cpt_fee(
            fee_collector,
            dst_chain_id,
            new_payload_length,
            0
        );

        return fee
    }
    
    public entry fun supply(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_supply());

        let (pool, user, amount, app_payload) = bool_adapter_core::receive_deposit(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
            pool_manager_info,
            user_manager_info,
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
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        bool_message_fee: Coin<SUI>,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_withdraw());

        let (user, app_payload) = bool_adapter_core::receive_withdraw(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
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

        bool_adapter_core::send_withdraw(
            core_state,
            bool_global,
            storage::get_app_cap(storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            actual_amount,
            bool_message_fee,
            ctx
        );

        event::emit(RelayEvent {
            sequence: 0,
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
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        bool_message_fee: Coin<SUI>,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_borrow());

        let (user, app_payload) = bool_adapter_core::receive_withdraw(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
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

        bool_adapter_core::send_withdraw(
            core_state,
            bool_global,
            storage::get_app_cap(storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            amount,
            bool_message_fee,
            ctx
        );

        event::emit(RelayEvent {
            sequence: 0,
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
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_repay());

        let (pool, user, amount, app_payload) = bool_adapter_core::receive_deposit(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
            pool_manager_info,
            user_manager_info,
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
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_liquidate());

        let (sender, app_payload) = bool_adapter_core::receive_message(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
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
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_collateral());

        // Verify that a message is valid using the wormhole
        let (sender, app_payload) = bool_adapter_core::receive_message(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
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
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        // check server opcode
        check_server_opcode(&message_raw, server_opcode_lending_cancle_collateral());

        // Verify that a message is valid using the wormhole
        let (sender, app_payload) = bool_adapter_core::receive_message(
            core_state,
            bool_global,
            message_raw,
            signature,
            storage::get_app_cap(storage),
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
