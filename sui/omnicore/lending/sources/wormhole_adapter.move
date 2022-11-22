module lending::wormhole_adapter {
    use omnipool::pool::Pool;

    use lending::logic::{inner_supply, inner_withdraw, inner_borrow, inner_repay, inner_liquidate, decode_app_payload};
    use lending::storage::{StorageCap, Storage, get_app_cap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::PoolManagerInfo;
    use sui::bcs;
    use sui::coin::Coin;
    use sui::object::address_from_bytes;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    public entry fun supply(
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &mut Storage,
        cap: &StorageCap,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let (token_name, user, amount, _app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        inner_supply(cap, pool_manager_info, storage, bcs::to_bytes(&user), token_name, amount, ctx);
    }

    public entry fun withdraw<CoinType>(
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        pool: &mut Pool<CoinType>,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        cap: &StorageCap,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        chainid: u64,
        ctx: &mut TxContext
    ) {
        let (token_name, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let (_, token_amount, _) = decode_app_payload(app_payload);
        inner_withdraw(
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
            chainid,
            user,
            token_amount,
            token_name,
            wormhole_message_fee
        );
    }


    public entry fun borrow<CoinType>(
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        pool: &mut Pool<CoinType>,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        cap: &StorageCap,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        chainid: u64,
        ctx: &mut TxContext
    ) {
        let (token_name, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let user_address = bcs::to_bytes(&user);
        let (_, token_amount, _) = decode_app_payload(app_payload);
        inner_borrow(cap, pool_manager_info, storage, oracle, user_address, token_name, token_amount, ctx);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            pool,
            chainid,
            user,
            token_amount,
            token_name,
            wormhole_message_fee
        );
    }

    public entry fun repay(
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &mut Storage,
        cap: &StorageCap,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        let (token_name, user, amount, _app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        inner_repay(cap, pool_manager_info, storage, bcs::to_bytes(&user), token_name, amount, ctx);
    }

    public entry fun liquidate<CoinType>(
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        pool: &mut Pool<CoinType>,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        cap: &StorageCap,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        chainid: u64,
        ctx: &mut TxContext
    ) {
        let (withdraw_token_name, deposit_token_name, _user, amount, app_payload) = bridge_core::receive_deposit_and_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        let (_, _, user) = decode_app_payload(app_payload);
        let withdraw_amount = inner_liquidate(
            cap,
            pool_manager_info,
            storage,
            oracle,
            bcs::to_bytes(&user),
            withdraw_token_name,
            deposit_token_name,
            amount,
            ctx,
        );

        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            pool,
            chainid,
            address_from_bytes(user),
            withdraw_amount,
            withdraw_token_name,
            wormhole_message_fee
        );
    }
}
