module lending::wormhole_adapter {
    use std::option::{Self, Option};

    use dola_types::types::dola_chain_id;
    use lending::logic::{execute_supply, execute_withdraw, execute_borrow, execute_repay, execute_liquidate, decode_app_payload};
    use lending::storage::{StorageCap, Storage, get_app_cap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{PoolManagerInfo, get_id_by_pool, find_pool_by_chain};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{UserManagerInfo, get_dola_user_id};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    const EMUST_NONE: u64 = 0;

    const EMUST_SOME: u64 = 1;

    struct WormholeAdapater has key {
        id: UID,
        storage_cap: Option<StorageCap>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(WormholeAdapater {
            id: object::new(ctx),
            storage_cap: option::none()
        })
    }

    public fun transfer_storage_cap(
        wormhole_adapter: &mut WormholeAdapater,
        storage_cap: StorageCap
    ) {
        assert!(option::is_none(&wormhole_adapter.storage_cap), EMUST_NONE);
        option::fill(&mut wormhole_adapter.storage_cap, storage_cap);
    }

    fun get_storage_cap(wormhole_adapter: &WormholeAdapater): &StorageCap {
        assert!(option::is_some(&wormhole_adapter.storage_cap), EMUST_SOME);
        option::borrow(&wormhole_adapter.storage_cap)
    }

    public entry fun supply(
        wormhole_adapter: &WormholeAdapater,
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
        let (pool, user, amount, _app_payload) = bridge_core::receive_deposit(
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
    }

    public entry fun withdraw(
        wormhole_adapter: &WormholeAdapater,
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
        let (_, token_amount, receiver, _) = decode_app_payload(app_payload);

        let dst_chain = dola_chain_id(&receiver);
        let dst_pool = find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        execute_withdraw(
            cap,
            storage,
            oracle,
            pool_manager_info,
            dola_user_id,
            dola_pool_id,
            token_amount,
        );
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            token_amount,
            wormhole_message_fee
        );
    }


    public entry fun borrow(
        wormhole_adapter: &WormholeAdapater,
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
        let (_, token_amount, receiver, _) = decode_app_payload(app_payload);

        let dst_chain = dola_chain_id(&receiver);
        let dst_pool = find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        execute_borrow(cap, pool_manager_info, storage, oracle, dola_user_id, dola_pool_id, token_amount);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            token_amount,
            wormhole_message_fee
        );
    }

    public entry fun repay(
        wormhole_adapter: &WormholeAdapater,
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
        let (pool, user, amount, _app_payload) = bridge_core::receive_deposit(
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
    }

    public entry fun liquidate(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (deposit_pool, _deposit_user, deposit_amount, withdraw_pool, _withdraw_user, _app_id, app_payload) = bridge_core::receive_deposit_and_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        let (_, _, receiver, liquidate_user_id) = decode_app_payload(app_payload);

        let dst_chain = dola_chain_id(&receiver);
        let deposit_dola_pool_id = get_id_by_pool(pool_manager_info, deposit_pool);
        let withdraw_dola_pool_id = get_id_by_pool(pool_manager_info, withdraw_pool);
        let dst_pool = find_pool_by_chain(pool_manager_info, withdraw_dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        let withdraw_amount = execute_liquidate(
            cap,
            pool_manager_info,
            storage,
            oracle,
            liquidate_user_id,
            withdraw_dola_pool_id,
            deposit_dola_pool_id,
            deposit_amount,
        );

        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            withdraw_amount,
            wormhole_message_fee
        );
    }
}
