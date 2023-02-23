module lending_core::lending_wormhole_adapter {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{dola_chain_id, DolaAddress, encode_dola_address, decode_dola_address, dola_address};
    use lending_core::logic::{Self, execute_supply, execute_withdraw, execute_borrow, execute_repay, execute_liquidate};
    use lending_core::storage::{StorageCap, Storage, get_app_cap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{PoolManagerInfo, get_id_by_pool, find_pool_by_chain, get_pool_liquidity};
    use serde::serde::{serialize_u16, serialize_u64, serialize_vector, serialize_u8, deserialize_u16, deserialize_u64, vector_slice, deserialize_u8};
    use sui::coin::Coin;
    use sui::event::emit;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{UserManagerInfo, get_dola_user_id};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    const AS_COLLATERAL: u8 = 7;

    const CANCLE_AS_COLLATERAL: u8 = 8;

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
        amount: u64,
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
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (pool, user, amount, app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            ctx
        );
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = get_dola_user_id(user_manager_info, user);
        execute_supply(
            cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount
        );
        let (source_chain_id, nonce, call_type, amount, receiver, _) = decode_app_payload(app_payload);
        assert!(call_type == SUPPLY, EINVALID_CALL_TYPE);
        emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address(&receiver),
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
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (pool, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = get_dola_user_id(user_manager_info, user);
        let (source_chain_id, nonce, call_type, amount, receiver, _) = decode_app_payload(app_payload);
        assert!(call_type == WITHDRAW, EINVALID_CALL_TYPE);
        let dst_chain = dola_chain_id(&receiver);
        let dst_pool = find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // If the withdrawal exceeds the user's balance, use the maximum withdrawal
        let actual_amount = execute_withdraw(
            cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount,
        );

        // Check pool liquidity
        let pool_liquidity = get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (actual_amount as u128), ENOT_ENOUGH_LIQUIDITY);

        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            actual_amount,
            wormhole_message_fee
        );
        emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address(&receiver),
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
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (pool, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = get_dola_user_id(user_manager_info, user);
        let (source_chain_id, nonce, call_type, amount, receiver, _) = decode_app_payload(app_payload);
        assert!(call_type == BORROW, EINVALID_CALL_TYPE);

        let dst_chain = dola_chain_id(&receiver);
        let dst_pool = find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        // Check pool liquidity
        let pool_liquidity = get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u128), ENOT_ENOUGH_LIQUIDITY);

        execute_borrow(cap, pool_manager_info, storage, oracle, dola_user_id, dola_pool_id, amount);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            source_chain_id,
            nonce,
            amount,
            wormhole_message_fee
        );
        emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address(&receiver),
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
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (pool, user, amount, app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            user_manager_info,
            ctx
        );
        let dola_pool_id = get_id_by_pool(pool_manager_info, pool);
        let dola_user_id = get_dola_user_id(user_manager_info, user);
        execute_repay(cap, pool_manager_info, storage, oracle, dola_user_id, dola_pool_id, amount);
        let (source_chain_id, nonce, call_type, amount, receiver, _) = decode_app_payload(app_payload);
        assert!(call_type == REPAY, EINVALID_CALL_TYPE);
        emit(LendingCoreEvent {
            nonce,
            sender_user_id: dola_user_id,
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            dola_pool_id,
            receiver: dola_address(&receiver),
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
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (deposit_pool, deposit_user, deposit_amount, withdraw_pool, _app_id, app_payload) = bridge_core::receive_deposit_and_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        let (source_chain_id, nonce, call_type, _, _, liquidate_user_id) = decode_app_payload(app_payload);
        assert!(call_type == LIQUIDATE, EINVALID_CALL_TYPE);

        let liquidator = get_dola_user_id(user_manager_info, deposit_user);
        let deposit_dola_pool_id = get_id_by_pool(pool_manager_info, deposit_pool);
        let withdraw_dola_pool_id = get_id_by_pool(pool_manager_info, withdraw_pool);
        execute_supply(
            cap,
            pool_manager_info,
            storage,
            oracle,
            liquidator,
            deposit_dola_pool_id,
            deposit_amount
        );

        execute_liquidate(
            cap,
            pool_manager_info,
            storage,
            oracle,
            liquidator,
            liquidate_user_id,
            withdraw_dola_pool_id,
            deposit_dola_pool_id,
        );

        emit(LendingCoreEvent {
            nonce,
            sender_user_id: liquidator,
            source_chain_id,
            dst_chain_id: dola_chain_id(&deposit_user),
            dola_pool_id: withdraw_dola_pool_id,
            receiver: dola_address(&deposit_user),
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
        vaa: vector<u8>
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        // Verify that a message is valid using the wormhole
        let app_payload = bridge_core::receive_app_message(wormhole_state, core_state, vaa);
        let (sender, dola_pool_ids, call_type) = decode_app_helper_payload(app_payload);
        assert!(call_type == AS_COLLATERAL, EINVALID_CALL_TYPE);
        let dola_user_id = get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            logic::as_collateral(cap, pool_manager_info, storage, oracle, dola_user_id, *dola_pool_id);
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
        vaa: vector<u8>
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        // Verify that a message is valid using the wormhole
        let app_payload = bridge_core::receive_app_message(wormhole_state, core_state, vaa);
        let (sender, dola_pool_ids, call_type) = decode_app_helper_payload(app_payload);
        assert!(call_type == CANCLE_AS_COLLATERAL, EINVALID_CALL_TYPE);
        let dola_user_id = get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            logic::as_collateral(cap, pool_manager_info, storage, oracle, dola_user_id, *dola_pool_id);
            i = i + 1;
        };
    }

    // App helper function payload
    public fun encode_app_helper_payload(
        sender: DolaAddress,
        dola_pool_ids: vector<u16>,
        call_type: u8,
    ) {
        let payload = vector::empty<u8>();

        let sender = encode_dola_address(sender);
        serialize_u16(&mut payload, (vector::length(&sender) as u16));
        serialize_vector(&mut payload, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        serialize_u16(&mut payload, (pool_ids_length as u16));
        let i = 0;
        while (i < pool_ids_length) {
            serialize_u16(&mut payload, *vector::borrow(&dola_pool_ids, i));
            i = i + 1;
        };

        serialize_u8(&mut payload, call_type);
    }

    public fun decode_app_helper_payload(
        payload: vector<u8>
    ): (DolaAddress, vector<u16>, u8) {
        let index = 0;
        let data_len;

        data_len = 2;
        let sender_length = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = (sender_length as u64);
        let sender = decode_dola_address(vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let pool_ids_length = deserialize_u16(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        let i = 0;
        let dola_pool_ids = vector::empty<u16>();
        while (i < pool_ids_length) {
            data_len = 2;
            let dola_pool_id = deserialize_u16(&vector_slice(&payload, index, index + data_len));
            vector::push_back(&mut dola_pool_ids, dola_pool_id);
            index = index + data_len;
            i = i + 1;
        };

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&payload), EINVALID_LENGTH);
        (sender, dola_pool_ids, call_type)
    }

    // App core function payload
    public fun encode_app_payload(
        source_chain_id: u16,
        nonce: u64,
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serialize_u16(&mut payload, source_chain_id);
        serialize_u64(&mut payload, nonce);

        serialize_u64(&mut payload, amount);
        let receiver = encode_dola_address(receiver);
        serialize_u16(&mut payload, (vector::length(&receiver) as u16));
        serialize_vector(&mut payload, receiver);
        serialize_u64(&mut payload, liquidate_user_id);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (u16, u64, u8, u64, DolaAddress, u64) {
        let index = 0;
        let data_len;

        data_len = 2;
        let source_chain_id = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let receive_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = (receive_length as u64);
        let receiver = decode_dola_address(vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let liquidate_user_id = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (source_chain_id, nonce, call_type, amount, receiver, liquidate_user_id)
    }
}
