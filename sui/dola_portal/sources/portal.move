module dola_portal::portal {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{DolaAddress, encode_dola_address, decode_dola_address, convert_address_to_dola, create_dola_address};
    use lending_core::storage::{StorageCap, Storage};
    use omnipool::pool::{Pool, normal_amount, Self, PoolCap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerCap, PoolManagerInfo};
    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64, serialize_u16, serialize_vector, deserialize_u16};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use user_manager::user_manager::{Self, UserManagerInfo, UserManagerCap};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::CoreState;
    use wormhole_bridge::bridge_pool::PoolState;

    const EINVALID_LENGTH: u64 = 0;

    const EAMOUNT_NOT_ENOUGH: u64 = 1;

    const EAMOUNT_MUST_ZERO: u64 = 2;

    const EMUST_NONE: u64 = 3;

    const EMUST_SOME: u64 = 4;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 5;

    const LENDING_APP_ID: u16 = 1;

    /// Call types for relayer call
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    const U64_MAX: u64 = 18446744073709551615;

    struct LendingPortal has key {
        id: UID,
        pool_cap: Option<PoolCap>,
        pool_manager_cap: Option<PoolManagerCap>,
        user_manager_cap: Option<UserManagerCap>,
        storage_cap: Option<StorageCap>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(LendingPortal {
            id: object::new(ctx),
            pool_cap: option::none(),
            pool_manager_cap: option::none(),
            user_manager_cap: option::none(),
            storage_cap: option::none()
        })
    }

    public fun transfer_pool_cap(
        lending_portal: &mut LendingPortal,
        pool_cap: PoolCap
    ) {
        assert!(option::is_none(&lending_portal.pool_cap), EMUST_NONE);
        option::fill(&mut lending_portal.pool_cap, pool_cap);
    }

    public fun transfer_pool_manager_cap(
        lending_portal: &mut LendingPortal,
        pool_manager_cap: PoolManagerCap
    ) {
        assert!(option::is_none(&lending_portal.pool_manager_cap), EMUST_NONE);
        option::fill(&mut lending_portal.pool_manager_cap, pool_manager_cap);
    }

    public fun transfer_user_manager_cap(
        lending_portal: &mut LendingPortal,
        user_manager_cap: UserManagerCap
    ) {
        assert!(option::is_none(&lending_portal.user_manager_cap), EMUST_NONE);
        option::fill(&mut lending_portal.user_manager_cap, user_manager_cap);
    }

    public fun transfer_storage_cap(
        lending_portal: &mut LendingPortal,
        storage_cap: StorageCap
    ) {
        assert!(option::is_none(&lending_portal.storage_cap), EMUST_NONE);
        option::fill(&mut lending_portal.storage_cap, storage_cap);
    }

    public fun merge_coin<CoinType>(
        coins: vector<Coin<CoinType>>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        let len = vector::length(&coins);
        if (len > 0) {
            vector::reverse(&mut coins);
            let base_coin = vector::pop_back(&mut coins);
            while (!vector::is_empty(&coins)) {
                coin::join(&mut base_coin, vector::pop_back(&mut coins));
            };
            vector::destroy_empty(coins);
            let sum_amount = coin::value(&base_coin);
            let split_amount = amount;
            if (amount == U64_MAX) {
                split_amount = sum_amount;
            };
            assert!(sum_amount >= split_amount, EAMOUNT_NOT_ENOUGH);
            if (coin::value(&base_coin) > split_amount) {
                let split_coin = coin::split(&mut base_coin, split_amount, ctx);
                transfer::transfer(base_coin, tx_context::sender(ctx));
                split_coin
            }else {
                base_coin
            }
        }else {
            vector::destroy_empty(coins);
            assert!(amount == 0, EAMOUNT_MUST_ZERO);
            coin::zero<CoinType>(ctx)
        }
    }

    public entry fun send_binding(
        lending_portal: &LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        bind_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let user = convert_address_to_dola(user);
        let bind_address = create_dola_address(dola_chain_id, bind_address);
        if (user == bind_address) {
            user_manager::register_dola_user_id(
                option::borrow(&lending_portal.user_manager_cap),
                user_manager_info,
                user
            );
        } else {
            user_manager::binding_user_address(
                option::borrow(&lending_portal.user_manager_cap),
                user_manager_info,
                user,
                bind_address
            );
        };
    }

    public entry fun send_unbinding(
        lending_portal: &LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        unbind_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let user = convert_address_to_dola(user);
        let unbind_address = create_dola_address(dola_chain_id, unbind_address);
        user_manager::unbinding_user_address(
            option::borrow(&lending_portal.user_manager_cap),
            user_manager_info,
            user,
            unbind_address
        );
    }

    public entry fun supply<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        deposit_coins: vector<Coin<CoinType>>,
        deposit_amount: u64,
        ctx: &mut TxContext
    ) {
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let pool_addr = dola_types::types::convert_pool_to_dola<CoinType>();
        let deposit_coin = merge_coin<CoinType>(deposit_coins, deposit_amount, ctx);
        let deposit_amount = normal_amount(pool, coin::value(&deposit_coin));
        let app_payload = encode_app_payload(SUPPLY, deposit_amount, user_addr, 0);
        // Deposit the token into the pool
        omnipool::pool::deposit_to(
            pool,
            deposit_coin,
            LENDING_APP_ID,
            app_payload,
            ctx
        );

        // Add pool liquidity for dola protocol
        pool_manager::add_liquidity(
            option::borrow(&lending_portal.pool_manager_cap),
            pool_manager_info,
            pool_addr,
            LENDING_APP_ID,
            deposit_amount,
            ctx
        );
        // Reigster user id for user
        if (!user_manager::user_manager::is_dola_user(user_manager_info, user_addr)) {
            user_manager::user_manager::register_dola_user_id(
                option::borrow(&lending_portal.user_manager_cap),
                user_manager_info,
                user_addr
            );
        };
        // Execute supply logic in lending_core app
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);
        lending_core::logic::execute_supply(
            option::borrow(&lending_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            deposit_amount
        );
    }

    /// Since the protocol is deployed on sui, withdraw on sui can be skipped across the chain
    public entry fun withdraw_local<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let dst_chain = dola_types::types::get_native_dola_chain_id();
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let pool_addr = dola_types::types::convert_pool_to_dola<CoinType>();
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);

        // Locate withdrawal pool
        let dst_pool = pool_manager::pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // Check pool liquidity
        let pool_liquidity = pool_manager::pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u128), ENOT_ENOUGH_LIQUIDITY);

        // Execute withdraw logic in lending_core app
        lending_core::logic::execute_withdraw(
            option::borrow(&lending_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount,
        );
        // Remove pool liquidity for dst ppol
        pool_manager::remove_liquidity(
            option::borrow(&lending_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            amount
        );
        // Local withdraw
        pool::inner_withdraw(option::borrow(&lending_portal.pool_cap), pool, user_addr, amount, pool_addr, ctx);
    }

    public entry fun withdraw_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        lending_portal: &LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let receiver = dola_types::types::create_dola_address(dst_chain, receiver);
        let pool_addr = dola_types::types::create_dola_address(dst_chain, pool);
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);

        // Locate withdrawal pool
        let dst_pool = pool_manager::pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // Check pool liquidity
        let pool_liquidity = pool_manager::pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u128), ENOT_ENOUGH_LIQUIDITY);

        // Execute withdraw logic in lending_core app
        lending_core::logic::execute_withdraw(
            option::borrow(&lending_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount,
        );
        // Remove pool liquidity for dst ppol
        pool_manager::remove_liquidity(
            option::borrow(&lending_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            amount
        );

        // Cross-chain withdraw
        wormhole_bridge::bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            lending_core::storage::get_app_cap(option::borrow(&lending_portal.storage_cap), storage),
            pool_manager_info,
            dst_pool,
            receiver,
            amount,
            coin::zero<SUI>(ctx)
        );
    }

    /// Since the protocol is deployed on sui, borrow on sui can be skipped across the chain
    public entry fun borrow_local<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let dst_chain = dola_types::types::get_native_dola_chain_id();
        let pool_addr = dola_types::types::convert_pool_to_dola<CoinType>();
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);

        // Locate withdraw pool
        let dst_pool = pool_manager::pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        // Check pool liquidity
        let pool_liquidity = pool_manager::pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u128), ENOT_ENOUGH_LIQUIDITY);

        // Execute borrow logic in lending_core app
        lending_core::logic::execute_borrow(
            option::borrow(&lending_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount
        );
        // Remove pool liquidity
        pool_manager::remove_liquidity(
            option::borrow(&lending_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            amount
        );
        // Local borrow
        pool::inner_withdraw(option::borrow(&lending_portal.pool_cap), pool, user_addr, amount, pool_addr, ctx);
    }

    public entry fun borrow_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        lending_portal: &LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let receiver = dola_types::types::create_dola_address(dst_chain, receiver);
        let pool_addr = dola_types::types::create_dola_address(dst_chain, pool);
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);

        // Locate withdraw pool
        let dst_pool = pool_manager::pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        // Check pool liquidity
        let pool_liquidity = pool_manager::pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u128), ENOT_ENOUGH_LIQUIDITY);

        // Execute borrow logic in lending_core app
        lending_core::logic::execute_borrow(
            option::borrow(&lending_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount
        );
        // Remove pool liquidity
        pool_manager::remove_liquidity(
            option::borrow(&lending_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            amount
        );
        // Cross-chain borrow
        wormhole_bridge::bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            lending_core::storage::get_app_cap(option::borrow(&lending_portal.storage_cap), storage),
            pool_manager_info,
            dst_pool,
            receiver,
            amount,
            coin::zero<SUI>(ctx)
        );
    }

    public entry fun repay<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        ctx: &mut TxContext
    ) {
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let pool_addr = dola_types::types::convert_pool_to_dola<CoinType>();
        let repay_coin = merge_coin<CoinType>(repay_coins, repay_amount, ctx);
        let repay_amount = normal_amount(pool, coin::value(&repay_coin));
        let app_payload = encode_app_payload(SUPPLY, repay_amount, user_addr, 0);
        // Deposit the token into the pool
        omnipool::pool::deposit_to(
            pool,
            repay_coin,
            LENDING_APP_ID,
            app_payload,
            ctx
        );

        pool_manager::add_liquidity(
            option::borrow(&lending_portal.pool_manager_cap),
            pool_manager_info,
            pool_addr,
            LENDING_APP_ID,
            repay_amount,
            ctx
        );
        if (!user_manager::user_manager::is_dola_user(user_manager_info, user_addr)) {
            user_manager::user_manager::register_dola_user_id(
                option::borrow(&lending_portal.user_manager_cap),
                user_manager_info,
                user_addr
            );
        };

        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);
        lending_core::logic::execute_repay(
            option::borrow(&lending_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            repay_amount
        );
    }

    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        receiver: vector<u8>,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coins: vector<Coin<DebtCoinType>>,
        debt_amount: u64,
        liquidate_user_id: u64,
        ctx: &mut TxContext
    ) {
        let debt_coin = merge_coin<DebtCoinType>(debt_coins, debt_amount, ctx);

        let receiver = dola_types::types::create_dola_address(dst_chain, receiver);

        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        let app_payload = encode_app_payload(LIQUIDATE, normal_amount(debt_pool, coin::value(&debt_coin)),
            receiver, liquidate_user_id);
        wormhole_bridge::bridge_pool::send_deposit_and_withdraw<DebtCoinType, CollateralCoinType>(
            pool_state,
            wormhole_state,
            wormhole_message_fee,
            debt_pool,
            debt_coin,
            LENDING_APP_ID,
            app_payload,
            ctx
        );
    }

    public fun encode_app_payload(
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u64(&mut payload, amount);
        let receiver = encode_dola_address(receiver);
        serialize_u16(&mut payload, (vector::length(&receiver) as u16));
        serialize_vector(&mut payload, receiver);
        serialize_u64(&mut payload, liquidate_user_id);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (u8, u64, DolaAddress, u64) {
        let index = 0;
        let data_len;

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

        (call_type, amount, receiver, liquidate_user_id)
    }

    #[test]
    fun test_encode_decode() {
        let user = @0x11;
        let payload = encode_app_payload(WITHDRAW, 100000000, dola_types::types::convert_address_to_dola(user), 0);
        let (call_type, amount, user_addr, _) = decode_app_payload(payload);
        assert!(call_type == WITHDRAW, 0);
        assert!(amount == 100000000, 0);
        assert!(user_addr == dola_types::types::convert_address_to_dola(user), 0);
    }
}
