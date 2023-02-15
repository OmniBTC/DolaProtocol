module dola_portal::portal {
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{convert_address_to_dola, create_dola_address, get_native_dola_chain_id, dola_address};
    use lending_core::storage::{StorageCap, Storage};
    use omnipool::pool::{Pool, normal_amount, Self, PoolCap};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerCap, PoolManagerInfo};
    use sui::coin::{Self, Coin};
    use sui::event::emit;
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

    const BINDING: u8 = 5;

    const UNBINDING: u8 = 6;

    const U64_MAX: u64 = 18446744073709551615;

    struct DolaPortal has key {
        id: UID,
        pool_cap: Option<PoolCap>,
        pool_manager_cap: Option<PoolManagerCap>,
        user_manager_cap: Option<UserManagerCap>,
        storage_cap: Option<StorageCap>,
        nonce: u64
    }

    /// Events
    struct ProtocolPortalEvent has drop, copy {
        nonce: u64,
        sender: address,
        source_chain_id: u16,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    // Since the protocol can be directly connected on sui,
    // this is a special event for the sui chain.
    struct LocalProtocolEvent has drop, copy {
        nonce: u64,
        sender: address,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    struct LendingPortalEvent has drop, copy {
        nonce: u64,
        sender: address,
        dola_pool_address: vector<u8>,
        source_chain_id: u16,
        dst_chain_id: u16,
        receiver: vector<u8>,
        amount: u64,
        call_type: u8
    }

    // Since the protocol can be directly connected on sui,
    // this is a special event for the sui chain.
    struct LocalLendingEvent has drop, copy {
        nonce: u64,
        sender: address,
        dola_pool_address: vector<u8>,
        amount: u64,
        call_type: u8
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(DolaPortal {
            id: object::new(ctx),
            pool_cap: option::none(),
            pool_manager_cap: option::none(),
            user_manager_cap: option::none(),
            storage_cap: option::none(),
            nonce: 0
        })
    }

    fun increment_nonce(dola_portal: &mut DolaPortal): u64 {
        let nonce = dola_portal.nonce;
        dola_portal.nonce = dola_portal.nonce + 1;
        nonce
    }

    public fun transfer_pool_cap(
        dola_portal: &mut DolaPortal,
        pool_cap: PoolCap
    ) {
        assert!(option::is_none(&dola_portal.pool_cap), EMUST_NONE);
        option::fill(&mut dola_portal.pool_cap, pool_cap);
    }

    public fun transfer_pool_manager_cap(
        dola_portal: &mut DolaPortal,
        pool_manager_cap: PoolManagerCap
    ) {
        assert!(option::is_none(&dola_portal.pool_manager_cap), EMUST_NONE);
        option::fill(&mut dola_portal.pool_manager_cap, pool_manager_cap);
    }

    public fun transfer_user_manager_cap(
        dola_portal: &mut DolaPortal,
        user_manager_cap: UserManagerCap
    ) {
        assert!(option::is_none(&dola_portal.user_manager_cap), EMUST_NONE);
        option::fill(&mut dola_portal.user_manager_cap, user_manager_cap);
    }

    public fun transfer_storage_cap(
        dola_portal: &mut DolaPortal,
        storage_cap: StorageCap
    ) {
        assert!(option::is_none(&dola_portal.storage_cap), EMUST_NONE);
        option::fill(&mut dola_portal.storage_cap, storage_cap);
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
        dola_portal: &mut DolaPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        bind_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let user = convert_address_to_dola(sender);
        let bind_dola_address = create_dola_address(dola_chain_id, bind_address);
        if (user == bind_dola_address) {
            user_manager::register_dola_user_id(
                option::borrow(&dola_portal.user_manager_cap),
                user_manager_info,
                user
            );
        } else {
            user_manager::binding_user_address(
                option::borrow(&dola_portal.user_manager_cap),
                user_manager_info,
                user,
                bind_dola_address
            );
        };
        emit(LocalProtocolEvent {
            nonce: increment_nonce(dola_portal),
            sender,
            user_chain_id: dola_chain_id,
            user_address: bind_address,
            call_type: BINDING
        })
    }

    public entry fun send_unbinding(
        dola_portal: &mut DolaPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        unbind_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let user = convert_address_to_dola(sender);
        let unbind_dola_address = create_dola_address(dola_chain_id, unbind_address);
        user_manager::unbinding_user_address(
            option::borrow(&dola_portal.user_manager_cap),
            user_manager_info,
            user,
            unbind_dola_address
        );

        emit(LocalProtocolEvent {
            nonce: increment_nonce(dola_portal),
            sender,
            user_chain_id: dola_chain_id,
            user_address: unbind_address,
            call_type: UNBINDING
        })
    }

    public entry fun supply<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_portal: &mut DolaPortal,
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
        let nonce = increment_nonce(dola_portal);
        let app_payload = lending_core::lending_wormhole_adapter::encode_app_payload(
            get_native_dola_chain_id(),
            nonce,
            SUPPLY,
            deposit_amount,
            user_addr,
            0
        );
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
            option::borrow(&dola_portal.pool_manager_cap),
            pool_manager_info,
            pool_addr,
            LENDING_APP_ID,
            deposit_amount,
            ctx
        );
        // Reigster user id for user
        if (!user_manager::user_manager::is_dola_user(user_manager_info, user_addr)) {
            user_manager::user_manager::register_dola_user_id(
                option::borrow(&dola_portal.user_manager_cap),
                user_manager_info,
                user_addr
            );
        };
        // Execute supply logic in lending_core app
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);
        lending_core::logic::execute_supply(
            option::borrow(&dola_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            deposit_amount
        );

        emit(LocalLendingEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address(&pool_addr),
            amount: deposit_amount,
            call_type: SUPPLY
        })
    }

    /// Since the protocol is deployed on sui, withdraw on sui can be skipped across the chain
    public entry fun withdraw_local<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_portal: &mut DolaPortal,
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

        // Execute withdraw logic in lending_core app
        let actual_amount = lending_core::logic::execute_withdraw(
            option::borrow(&dola_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount,
        );

        // Check pool liquidity
        let pool_liquidity = pool_manager::pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (actual_amount as u128), ENOT_ENOUGH_LIQUIDITY);

        // Remove pool liquidity for dst ppol
        pool_manager::remove_liquidity(
            option::borrow(&dola_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            actual_amount
        );

        // Local withdraw
        pool::inner_withdraw(option::borrow(&dola_portal.pool_cap), pool, user_addr, amount, pool_addr, ctx);

        emit(LocalLendingEvent {
            nonce: increment_nonce(dola_portal),
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address(&pool_addr),
            amount: actual_amount,
            call_type: WITHDRAW
        })
    }

    public entry fun withdraw_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        dola_portal: &mut DolaPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let receiver = dola_types::types::create_dola_address(dst_chain, receiver_addr);
        let pool_addr = dola_types::types::create_dola_address(dst_chain, pool);
        let user_addr = dola_types::types::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);

        // Locate withdrawal pool
        let dst_pool = pool_manager::pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // Execute withdraw logic in lending_core app
        let actual_amount = lending_core::logic::execute_withdraw(
            option::borrow(&dola_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount,
        );

        // Check pool liquidity
        let pool_liquidity = pool_manager::pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (actual_amount as u128), ENOT_ENOUGH_LIQUIDITY);

        // Remove pool liquidity for dst ppol
        pool_manager::remove_liquidity(
            option::borrow(&dola_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            actual_amount
        );

        let nonce = increment_nonce(dola_portal);
        // Cross-chain withdraw
        wormhole_bridge::bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            lending_core::storage::get_app_cap(option::borrow(&dola_portal.storage_cap), storage),
            pool_manager_info,
            dst_pool,
            receiver,
            get_native_dola_chain_id(),
            nonce,
            actual_amount,
            coin::zero<SUI>(ctx)
        );

        emit(LendingPortalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address(&pool_addr),
            source_chain_id: get_native_dola_chain_id(),
            dst_chain_id: dst_chain,
            receiver: receiver_addr,
            amount: actual_amount,
            call_type: WITHDRAW
        })
    }

    /// Since the protocol is deployed on sui, borrow on sui can be skipped across the chain
    public entry fun borrow_local<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_portal: &mut DolaPortal,
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
            option::borrow(&dola_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount
        );

        // Remove pool liquidity
        pool_manager::remove_liquidity(
            option::borrow(&dola_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            amount
        );
        // Local borrow
        pool::inner_withdraw(option::borrow(&dola_portal.pool_cap), pool, user_addr, amount, pool_addr, ctx);

        emit(LocalLendingEvent {
            nonce: increment_nonce(dola_portal),
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address(&pool_addr),
            amount,
            call_type: BORROW
        })
    }

    public entry fun borrow_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        dola_portal: &mut DolaPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let receiver = dola_types::types::create_dola_address(dst_chain, receiver_addr);
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
            option::borrow(&dola_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            amount
        );
        // Remove pool liquidity
        pool_manager::remove_liquidity(
            option::borrow(&dola_portal.pool_manager_cap),
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            amount
        );

        let nonce = increment_nonce(dola_portal);
        // Cross-chain borrow
        wormhole_bridge::bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            lending_core::storage::get_app_cap(option::borrow(&dola_portal.storage_cap), storage),
            pool_manager_info,
            dst_pool,
            receiver,
            get_native_dola_chain_id(),
            nonce,
            amount,
            coin::zero<SUI>(ctx)
        );

        emit(LendingPortalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address(&pool_addr),
            source_chain_id: get_native_dola_chain_id(),
            dst_chain_id: dst_chain,
            receiver: receiver_addr,
            amount,
            call_type: BORROW
        })
    }

    public entry fun repay<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_portal: &mut DolaPortal,
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
        let nonce = increment_nonce(dola_portal);
        let app_payload = lending_core::lending_wormhole_adapter::encode_app_payload(
            get_native_dola_chain_id(),
            nonce,
            SUPPLY,
            repay_amount,
            user_addr,
            0
        );
        // Deposit the token into the pool
        omnipool::pool::deposit_to(
            pool,
            repay_coin,
            LENDING_APP_ID,
            app_payload,
            ctx
        );

        pool_manager::add_liquidity(
            option::borrow(&dola_portal.pool_manager_cap),
            pool_manager_info,
            pool_addr,
            LENDING_APP_ID,
            repay_amount,
            ctx
        );
        if (!user_manager::user_manager::is_dola_user(user_manager_info, user_addr)) {
            user_manager::user_manager::register_dola_user_id(
                option::borrow(&dola_portal.user_manager_cap),
                user_manager_info,
                user_addr
            );
        };

        let dola_pool_id = pool_manager::pool_manager::get_id_by_pool(pool_manager_info, pool_addr);
        let dola_user_id = user_manager::user_manager::get_dola_user_id(user_manager_info, user_addr);
        lending_core::logic::execute_repay(
            option::borrow(&dola_portal.storage_cap),
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            repay_amount
        );

        emit(LocalLendingEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address(&pool_addr),
            amount: repay_amount,
            call_type: REPAY
        })
    }

    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        dola_portal: &mut DolaPortal,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u16,
        receiver: vector<u8>,
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
        let nonce = increment_nonce(dola_portal);
        let app_payload = lending_core::lending_wormhole_adapter::encode_app_payload(
            get_native_dola_chain_id(),
            nonce,
            LIQUIDATE,
            normal_amount(debt_pool, coin::value(&debt_coin)),
            receiver,
            liquidate_user_id
        );
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

    #[test]
    fun test_encode_decode() {
        let user = @0x11;
        let payload = lending_core::lending_wormhole_adapter::encode_app_payload(
            0,
            0,
            WITHDRAW,
            100000000,
            dola_types::types::convert_address_to_dola(user),
            0
        );
        let (_, _, call_type, amount, user_addr, _) = lending_core::logic::decode_app_payload(payload);
        assert!(call_type == WITHDRAW, 0);
        assert!(amount == 100000000, 0);
        assert!(user_addr == dola_types::types::convert_address_to_dola(user), 0);
    }
}
