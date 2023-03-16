// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Lending front-end contract portal
module dola_portal::lending {
    use std::option;
    use std::vector;

    use dola_types::dola_address;
    use dola_types::dola_contract::{Self, DolaContract, DolaContractRegistry};
    use governance::genesis::GovernanceCap;
    use lending_core::lending_codec;
    use lending_core::storage::{Self, StorageCap, Storage};
    use omnipool::dola_pool::{Self, Pool, PoolApproval};
    use omnipool::wormhole_adapter_pool::{Self, PoolState};
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
    use wormhole_adapter_core::wormhole_adapter_core::{Self, CoreState};

    /// Errors

    const EAMOUNT_NOT_ENOUGH: u64 = 1;

    const EAMOUNT_MUST_ZERO: u64 = 2;

    const EMUST_NONE: u64 = 3;

    const EMUST_SOME: u64 = 4;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 5;

    /// App ID

    const LENDING_APP_ID: u16 = 1;

    /// Lending Call types
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    const U64_MAX: u64 = 18446744073709551615;

    struct LendingPortal has key {
        id: UID,
        /// Used to represent the contract address of this module in the Dola protocol
        dola_contract: DolaContract,
        // Allow modification of user_manager storage through UserManagerCap
        user_manager_cap: UserManagerCap,
        // Allow modification of pool_manager storage via PoolManagerCap
        pool_manager_cap: PoolManagerCap,
        // Allow modification of lending storage
        storage_cap: StorageCap,
        // Next nonce
        next_nonce: u64
    }

    /// Events

    /// Lending portal event
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
    struct LendingLocalEvent has drop, copy {
        nonce: u64,
        sender: address,
        dola_pool_address: vector<u8>,
        amount: u64,
        call_type: u8
    }

    public fun initialize_cap_with_governance(
        governance: &GovernanceCap,
        dola_contract_registry: &mut DolaContractRegistry,
        ctx: &mut TxContext
    ) {
        transfer::share_object(LendingPortal {
            id: object::new(ctx),
            dola_contract: dola_contract::create_dola_contract(dola_contract_registry, ctx),
            user_manager_cap: user_manager::register_cap_with_governance(governance),
            pool_manager_cap: pool_manager::register_cap_with_governance(governance),
            storage_cap: storage::register_cap_with_governance(governance),
            next_nonce: 0
        })
    }


    fun get_nonce(lending_portal: &mut LendingPortal): u64 {
        let nonce = lending_portal.next_nonce;
        lending_portal.next_nonce = lending_portal.next_nonce + 1;
        nonce
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

    public entry fun as_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        dola_pool_ids: vector<u16>,
        ctx: &mut TxContext
    ) {
        let sender = dola_address::convert_address_to_dola(tx_context::sender(ctx));

        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            lending_core::logic::as_collateral(
                &lending_portal.storage_cap,
                pool_manager_info,
                storage,
                oracle,
                dola_user_id,
                *dola_pool_id
            );
            i = i + 1;
        };
    }

    public entry fun cancel_as_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        dola_pool_ids: vector<u16>,
        ctx: &mut TxContext
    ) {
        let sender = dola_address::convert_address_to_dola(tx_context::sender(ctx));

        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);

        let pool_ids_length = vector::length(&dola_pool_ids);
        let i = 0;
        while (i < pool_ids_length) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, i);
            lending_core::logic::cancel_as_collateral(
                &lending_portal.storage_cap,
                pool_manager_info,
                storage,
                oracle,
                dola_user_id,
                *dola_pool_id
            );
            i = i + 1;
        };
    }

    public entry fun supply<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        deposit_coins: vector<Coin<CoinType>>,
        deposit_amount: u64,
        ctx: &mut TxContext
    ) {
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let deposit_coin = merge_coin<CoinType>(deposit_coins, deposit_amount, ctx);
        let deposit_amount = dola_pool::normal_amount(pool, coin::value(&deposit_coin));
        let nonce = get_nonce(lending_portal);

        // Deposit the token into the pool
        omnipool::dola_pool::deposit(
            pool,
            deposit_coin,
            LENDING_APP_ID,
            vector::empty(),
            ctx
        );

        // Add pool liquidity for dola protocol
        pool_manager::add_liquidity(
            &lending_portal.pool_manager_cap,
            pool_manager_info,
            pool_address,
            LENDING_APP_ID,
            (deposit_amount as u256),
        );
        // Reigster user id for user
        if (!user_manager::is_dola_user(user_manager_info, user_address)) {
            user_manager::register_dola_user_id(
                &lending_portal.user_manager_cap,
                user_manager_info,
                user_address
            );
        };
        // Execute supply logic in lending_core app
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
        lending_core::logic::execute_supply(
            &lending_portal.storage_cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            (deposit_amount as u256)
        );

        emit(LendingLocalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&pool_address),
            amount: deposit_amount,
            call_type: SUPPLY
        })
    }

    /// Since the protocol is deployed on sui, withdraw on sui can be skipped across the chain
    public entry fun withdraw_local<CoinType>(
        pool_approval: &PoolApproval,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let dst_chain = dola_address::get_native_dola_chain_id();
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);

        // Locate withdrawal pool
        let dst_pool = pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // Execute withdraw logic in lending_core app
        let actual_amount = lending_core::logic::execute_withdraw(
            &lending_portal.storage_cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            (amount as u256),
        );

        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= actual_amount, ENOT_ENOUGH_LIQUIDITY);

        // Remove pool liquidity for dst ppol
        pool_manager::remove_liquidity(
            &lending_portal.pool_manager_cap,
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            actual_amount
        );

        // Local withdraw
        dola_pool::withdraw(
            pool_approval,
            &lending_portal.dola_contract,
            pool,
            user_address,
            (actual_amount as u64),
            pool_address,
            ctx
        );

        emit(LendingLocalEvent {
            nonce: get_nonce(lending_portal),
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&pool_address),
            amount: (actual_amount as u64),
            call_type: WITHDRAW
        })
    }

    public entry fun withdraw_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        lending_portal: &mut LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let receiver = dola_address::create_dola_address(dst_chain, receiver_addr);
        let pool_address = dola_address::create_dola_address(dst_chain, pool);
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);

        // Locate withdrawal pool
        let dst_pool = pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // Execute withdraw logic in lending_core app
        let actual_amount = lending_core::logic::execute_withdraw(
            &lending_portal.storage_cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            (amount as u256),
        );

        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (actual_amount as u256), ENOT_ENOUGH_LIQUIDITY);

        // Remove pool liquidity for dst ppol
        pool_manager::remove_liquidity(
            &lending_portal.pool_manager_cap,
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            (actual_amount as u256)
        );

        let nonce = get_nonce(lending_portal);
        // Cross-chain withdraw
        wormhole_adapter_core::send_withdraw(
            wormhole_state,
            core_state,
            lending_core::storage::get_app_cap(&lending_portal.storage_cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            dola_address::get_native_dola_chain_id(),
            nonce,
            actual_amount,
            coin::zero<SUI>(ctx)
        );

        emit(LendingPortalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&pool_address),
            source_chain_id: dola_address::get_native_dola_chain_id(),
            dst_chain_id: dst_chain,
            receiver: receiver_addr,
            amount: (actual_amount as u64),
            call_type: WITHDRAW
        })
    }

    /// Since the protocol is deployed on sui, borrow on sui can be skipped across the chain
    public entry fun borrow_local<CoinType>(
        pool_approval: &PoolApproval,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let dst_chain = dola_address::get_native_dola_chain_id();
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);

        // Locate withdraw pool
        let dst_pool = pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);

        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u256), ENOT_ENOUGH_LIQUIDITY);

        // Execute borrow logic in lending_core app
        lending_core::logic::execute_borrow(
            &lending_portal.storage_cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            (amount as u256)
        );

        // Remove pool liquidity
        pool_manager::remove_liquidity(
            &lending_portal.pool_manager_cap,
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            (amount as u256)
        );
        // Local borrow
        dola_pool::withdraw(
            pool_approval,
            &lending_portal.dola_contract,
            pool,
            user_address,
            amount,
            pool_address,
            ctx
        );

        emit(LendingLocalEvent {
            nonce: get_nonce(lending_portal),
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&pool_address),
            amount,
            call_type: BORROW
        })
    }

    public entry fun borrow_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        lending_portal: &mut LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let receiver = dola_address::create_dola_address(dst_chain, receiver_addr);
        let pool_address = dola_address::create_dola_address(dst_chain, pool);
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);

        // Locate withdraw pool
        let dst_pool = pool_manager::find_pool_by_chain(pool_manager_info, dola_pool_id, dst_chain);
        assert!(option::is_some(&dst_pool), EMUST_SOME);
        let dst_pool = option::destroy_some(dst_pool);
        // Check pool liquidity
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dst_pool);
        assert!(pool_liquidity >= (amount as u256), ENOT_ENOUGH_LIQUIDITY);

        // Execute borrow logic in lending_core app
        lending_core::logic::execute_borrow(
            &lending_portal.storage_cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            (amount as u256)
        );
        // Remove pool liquidity
        pool_manager::remove_liquidity(
            &lending_portal.pool_manager_cap,
            pool_manager_info,
            dst_pool,
            LENDING_APP_ID,
            (amount as u256)
        );

        let nonce = get_nonce(lending_portal);
        // Cross-chain borrow
        wormhole_adapter_core::send_withdraw(
            wormhole_state,
            core_state,
            lending_core::storage::get_app_cap(&lending_portal.storage_cap, storage),
            pool_manager_info,
            dst_pool,
            receiver,
            dola_address::get_native_dola_chain_id(),
            nonce,
            (amount as u256),
            coin::zero<SUI>(ctx)
        );

        emit(LendingPortalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&pool_address),
            source_chain_id: dola_address::get_native_dola_chain_id(),
            dst_chain_id: dst_chain,
            receiver: receiver_addr,
            amount,
            call_type: BORROW
        })
    }

    public entry fun repay<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        ctx: &mut TxContext
    ) {
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let repay_coin = merge_coin<CoinType>(repay_coins, repay_amount, ctx);
        let repay_amount = dola_pool::normal_amount(pool, coin::value(&repay_coin));
        let nonce = get_nonce(lending_portal);
        // Deposit the token into the pool
        omnipool::dola_pool::deposit(
            pool,
            repay_coin,
            LENDING_APP_ID,
            vector::empty(),
            ctx
        );

        pool_manager::add_liquidity(
            &lending_portal.pool_manager_cap,
            pool_manager_info,
            pool_address,
            LENDING_APP_ID,
            (repay_amount as u256),
        );
        if (!user_manager::is_dola_user(user_manager_info, user_address)) {
            user_manager::register_dola_user_id(
                &lending_portal.user_manager_cap,
                user_manager_info,
                user_address
            );
        };

        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool_address);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
        lending_core::logic::execute_repay(
            &lending_portal.storage_cap,
            pool_manager_info,
            storage,
            oracle,
            dola_user_id,
            dola_pool_id,
            (repay_amount as u256)
        );

        emit(LendingLocalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&pool_address),
            amount: repay_amount,
            call_type: REPAY
        })
    }

    public entry fun liquidate<DebtCoinType>(
        lending_portal: &mut LendingPortal,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coins: vector<Coin<DebtCoinType>>,
        liquidate_chain_id: u16,
        liquidate_pool_address: vector<u8>,
        debt_amount: u64,
        liquidate_user_id: u64,
        ctx: &mut TxContext
    ) {
        let debt_coin = merge_coin<DebtCoinType>(debt_coins, debt_amount, ctx);
        let debt_pool_address = dola_address::convert_pool_to_dola<DebtCoinType>();
        let receiver = dola_address::convert_address_to_dola(tx_context::sender(ctx));

        let withdraw_pool = dola_address::create_dola_address(liquidate_chain_id, liquidate_pool_address);

        let nonce = get_nonce(lending_portal);
        let app_payload = lending_codec::encode_liquidate_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            withdraw_pool,
            liquidate_user_id
        );

        wormhole_adapter_pool::send_deposit<DebtCoinType>(
            pool_state,
            wormhole_state,
            coin::zero<SUI>(ctx),
            debt_pool,
            debt_coin,
            LENDING_APP_ID,
            app_payload,
            ctx
        );

        emit(LendingPortalEvent {
            nonce,
            sender: tx_context::sender(ctx),
            dola_pool_address: dola_address::get_dola_address(&debt_pool_address),
            source_chain_id: dola_address::get_native_dola_chain_id(),
            dst_chain_id: dola_address::get_dola_chain_id(&receiver),
            receiver: dola_address::get_dola_address(&receiver),
            amount: debt_amount,
            call_type: LIQUIDATE
        })
    }
}
