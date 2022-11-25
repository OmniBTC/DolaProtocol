module lending::wormhole_adapter {
    use std::option::{Self, Option};

    use lending::logic::{execute_supply, execute_withdraw, execute_borrow, execute_repay, execute_liquidate, decode_app_payload};
    use lending::storage::{StorageCap, Storage, get_app_cap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::PoolManagerInfo;
    use sui::bcs;
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
        storage: &mut Storage,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (token_name, user, amount, _app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        execute_supply(cap, pool_manager_info, storage, bcs::to_bytes(&user), token_name, amount, ctx);
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
        let (pool, user, token_name, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let (_, token_amount, _, dst_chain) = decode_app_payload(app_payload);
        execute_withdraw(
            cap,
            storage,
            oracle,
            pool_manager_info,
            bcs::to_bytes(&user),
            token_name,
            token_amount,
            ctx
        );
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            pool,
            dst_chain,
            user,
            token_amount,
            token_name,
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
        let (pool, user, token_name, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let user_address = bcs::to_bytes(&user);
        let (_, token_amount, _, dst_chain) = decode_app_payload(app_payload);
        execute_borrow(cap, pool_manager_info, storage, oracle, user_address, token_name, token_amount, ctx);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            pool,
            dst_chain,
            user,
            token_amount,
            token_name,
            wormhole_message_fee
        );
    }

    public entry fun repay(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &mut Storage,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let cap = get_storage_cap(wormhole_adapter);
        let (token_name, user, amount, _app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        execute_repay(cap, pool_manager_info, storage, bcs::to_bytes(&user), token_name, amount, ctx);
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
        let (_deposit_pool, deposit_user, deposit_amount, deposit_token, withdraw_pool, withdraw_user, withdraw_token, _app_id, app_payload) = bridge_core::receive_deposit_and_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        let (_, _, _, dst_chain) = decode_app_payload(app_payload);
        let withdraw_amount = execute_liquidate(
            cap,
            pool_manager_info,
            storage,
            oracle,
            bcs::to_bytes(&withdraw_user),
            withdraw_token,
            deposit_token,
            deposit_amount,
            ctx,
        );

        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            withdraw_pool,
            dst_chain,
            deposit_user,
            withdraw_amount,
            withdraw_token,
            wormhole_message_fee
        );
    }
}
