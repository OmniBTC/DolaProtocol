module lending::wormhole_adapter {
    use std::option::{Self, Option};

    use lending::logic::{execute_supply, execute_withdraw, execute_borrow, execute_repay, execute_liquidate, decode_app_payload};
    use lending::storage::{StorageCap, Storage, get_app_cap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{PoolManagerInfo, get_pool_catalog, find_pool_by_chain};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
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
            ctx
        );
        let catalog = get_pool_catalog(pool_manager_info, pool);
        execute_supply(
            cap,
            pool_manager_info,
            storage,
            oracle,
            user,
            catalog,
            amount
        );
    }

    public entry fun withdraw(
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
        let (pool, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let catalog = get_pool_catalog(pool_manager_info, pool);
        let (dst_chain, _, token_amount, _) = decode_app_payload(app_payload);

        let dst_pool = find_pool_by_chain(pool_manager_info, catalog, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        execute_withdraw(
            cap,
            storage,
            oracle,
            pool_manager_info,
            user,
            catalog,
            token_amount,
        );
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            user,
            token_amount,
            wormhole_message_fee
        );
    }


    public entry fun borrow(
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
        let (pool, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let catalog = get_pool_catalog(pool_manager_info, pool);
        let user_address = user;
        let (dst_chain, _, token_amount, _) = decode_app_payload(app_payload);
        let dst_pool = find_pool_by_chain(pool_manager_info, catalog, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        execute_borrow(cap, pool_manager_info, storage, oracle, user_address, catalog, token_amount);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            user,
            token_amount,
            wormhole_message_fee
        );
    }

    public entry fun repay(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
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
            ctx
        );
        let catalog = get_pool_catalog(pool_manager_info, pool);
        execute_repay(cap, pool_manager_info, storage, oracle, user, catalog, amount);
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
        let (deposit_pool, deposit_user, deposit_amount, withdraw_pool, withdraw_user, _app_id, app_payload) = bridge_core::receive_deposit_and_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        let (dst_chain, _, _, _) = decode_app_payload(app_payload);
        let deposit_catalog = get_pool_catalog(pool_manager_info, deposit_pool);
        let withdraw_catalog= get_pool_catalog(pool_manager_info, withdraw_pool);
        let dst_pool = find_pool_by_chain(pool_manager_info, withdraw_catalog, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        let withdraw_amount = execute_liquidate(
            cap,
            pool_manager_info,
            storage,
            oracle,
            withdraw_user,
            withdraw_catalog,
            deposit_catalog,
            deposit_amount,
        );

        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            dst_pool,
            deposit_user,
            withdraw_amount,
            wormhole_message_fee
        );
    }
}
