module lending_core::lending_wormhole_adapter {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{dola_chain_id, DolaAddress, encode_dola_address, decode_dola_address, dola_address};
    use lending_core::logic::{execute_supply, execute_withdraw, execute_borrow, execute_repay, execute_liquidate};
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

    /// Errors
    const EMUST_NONE: u64 = 0;

    const EMUST_SOME: u64 = 1;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 2;

    const EINVALID_LENGTH: u64 = 3;

    struct WormholeAdapter has key {
        id: UID,
        storage_cap: Option<StorageCap>
    }

    struct LendingCoreEvent has drop, copy {
        nonce: u64,
        source_chain_id: u16,
        dst_chain_id: u16,
        pool_address: vector<u8>,
        receiver: vector<u8>,
        amount: u64,
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
        emit(LendingCoreEvent {
            nonce,
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            pool_address: dola_address(&pool),
            receiver: dola_address(&receiver),
            amount,
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
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            pool_address: dola_address(&dst_pool),
            receiver: dola_address(&receiver),
            amount: actual_amount,
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
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            pool_address: dola_address(&dst_pool),
            receiver: dola_address(&receiver),
            amount,
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
        emit(LendingCoreEvent {
            nonce,
            source_chain_id,
            dst_chain_id: dola_chain_id(&receiver),
            pool_address: dola_address(&pool),
            receiver: dola_address(&receiver),
            amount,
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
        let (_, _, _, _, _, liquidate_user_id) = decode_app_payload(app_payload);

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
    }

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
