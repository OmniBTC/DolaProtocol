// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Lending front-end contract portal
module dola_protocol::lending_portal {
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use dola_protocol::dola_address::DolaAddress;
    use dola_protocol::dola_pool::Pool;
    use dola_protocol::genesis::{GovernanceCap, GovernanceGenesis};
    use dola_protocol::lending_core_storage::Storage;
    use dola_protocol::oracle::PriceOracle;
    use dola_protocol::pool_manager::PoolManagerInfo;
    use dola_protocol::user_manager::UserManagerInfo;
    use dola_protocol::wormhole_adapter_core::CoreState;
    use dola_protocol::wormhole_adapter_pool::PoolState;
    use wormhole::state::State as WormholeState;

    /// Errors

    const ENOT_FIND_POOL: u64 = 0;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 1;

    const ENOT_RELAYER: u64 = 2;

    const ENOT_ENOUGH_WORMHOLE_FEE: u64 = 3;

    const EAMOUNT_NOT_ZERO: u64 = 4;

    const DEPRECATED: u64 = 0;

    /// App ID
    const LENDING_APP_ID: u16 = 1;

    struct LendingPortal has key {
        id: UID,
        // Relayer
        relayer: address,
        // Next nonce
        next_nonce: u64
    }

    /// Events

    /// Relay Event
    struct RelayEvent has drop, copy {
        // Wormhole vaa sequence
        sequence: u64,
        // Transaction nonce
        nonce: u64,
        // Withdraw pool
        dst_pool: DolaAddress,
        // Relay fee amount
        fee_amount: u64,
        // Confirm that nonce is in the pool or core
        call_type: u8
    }

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

    fun init(ctx: &mut TxContext) {
        transfer::share_object(LendingPortal {
            id: object::new(ctx),
            relayer: tx_context::sender(ctx),
            next_nonce: 0
        })
    }

    fun get_nonce(lending_portal: &mut LendingPortal): u64 {
        let nonce = lending_portal.next_nonce;
        lending_portal.next_nonce = lending_portal.next_nonce + 1;
        nonce
    }

    /// === Governance Functions ===

    public fun set_relayer(
        _: &GovernanceCap,
        _lending_portal: &mut LendingPortal,
        _relayer: address
    ) {
        abort DEPRECATED
    }

    /// === Entry Functions ===

    public entry fun as_collateral(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _pool_manager_info: &mut PoolManagerInfo,
        _user_manager_info: &mut UserManagerInfo,
        _dola_pool_ids: vector<u16>,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun cancel_as_collateral(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _pool_manager_info: &mut PoolManagerInfo,
        _user_manager_info: &mut UserManagerInfo,
        _dola_pool_ids: vector<u16>,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    entry fun cancel_as_collateral_remote(
        _genesis: &GovernanceGenesis,
        _clock: &Clock,
        _pool_state: &mut PoolState,
        _lending_portal: &mut LendingPortal,
        _wormhole_state: &mut WormholeState,
        _dola_pool_ids: vector<u16>,
        _bridge_fee_coins: vector<Coin<SUI>>,
        _bridge_fee_amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun supply<CoinType>(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _lending_portal: &mut LendingPortal,
        _user_manager_info: &mut UserManagerInfo,
        _pool_manager_info: &mut PoolManagerInfo,
        _pool: &mut Pool<CoinType>,
        _deposit_coins: vector<Coin<CoinType>>,
        _deposit_amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    /// Since the protocol is deployed on sui, withdraw on sui can be skipped across the chain
    public entry fun withdraw_local<CoinType>(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _lending_portal: &mut LendingPortal,
        _pool_manager_info: &mut PoolManagerInfo,
        _user_manager_info: &mut UserManagerInfo,
        _pool: &mut Pool<CoinType>,
        _amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun withdraw_remote(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _core_state: &mut CoreState,
        _lending_portal: &mut LendingPortal,
        _wormhole_state: &mut WormholeState,
        _pool_manager_info: &mut PoolManagerInfo,
        _user_manager_info: &mut UserManagerInfo,
        _pool: vector<u8>,
        _receiver_addr: vector<u8>,
        _dst_chain: u16,
        _amount: u64,
        _bridge_fee_coins: vector<Coin<SUI>>,
        _bridge_fee_amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    /// Since the protocol is deployed on sui, borrow on sui can be skipped across the chain
    public entry fun borrow_local<CoinType>(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _lending_portal: &mut LendingPortal,
        _pool_manager_info: &mut PoolManagerInfo,
        _user_manager_info: &mut UserManagerInfo,
        _pool: &mut Pool<CoinType>,
        _amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun borrow_remote(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _core_state: &mut CoreState,
        _lending_portal: &mut LendingPortal,
        _wormhole_state: &mut WormholeState,
        _pool_manager_info: &mut PoolManagerInfo,
        _user_manager_info: &mut UserManagerInfo,
        _pool: vector<u8>,
        _receiver_addr: vector<u8>,
        _dst_chain: u16,
        _amount: u64,
        _bridge_fee_coins: vector<Coin<SUI>>,
        _bridge_fee_amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun repay<CoinType>(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _lending_portal: &mut LendingPortal,
        _user_manager_info: &mut UserManagerInfo,
        _pool_manager_info: &mut PoolManagerInfo,
        _pool: &mut Pool<CoinType>,
        _repay_coins: vector<Coin<CoinType>>,
        _repay_amount: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }

    public entry fun liquidate<DebtCoinType>(
        _genesis: &GovernanceGenesis,
        _storage: &mut Storage,
        _oracle: &mut PriceOracle,
        _clock: &Clock,
        _lending_portal: &mut LendingPortal,
        _user_manager_info: &mut UserManagerInfo,
        _pool_manager_info: &mut PoolManagerInfo,
        _debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        _debt_coins: vector<Coin<DebtCoinType>>,
        _debt_amount: u64,
        _liquidate_chain_id: u16,
        _liquidate_pool_address: vector<u8>,
        _liquidate_user_id: u64,
        _ctx: &mut TxContext
    ) {
        abort DEPRECATED
    }
}
