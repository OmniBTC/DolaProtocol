#!/bin/bash

# template
# module_function package module function args
function package_module_function() {
    local args=""
    local i=0
    for arg in "$@"
    do
      ((i+=1))
      if [ "$i" -gt 2 ]
      then
        args="$args $arg"
      fi
    done

    sui client call --package "$1" --module "$2" --function "$3" --args "$args" --gas-budget 10000
}

# public entry fun supply<CoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, pool: &mut Pool<CoinType>, deposit_coin: Coin<CoinType>, ctx: &mut TxContext )
functions lending_portal_lending_supply () {
    package_module_function "$@"
}

# public entry fun withdraw<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, dst_chain: u64, wormhole_message_fee: Coin<SUI>, amount: u64, ctx: &mut TxContext )
functions lending_portal_lending_withdraw () {
    package_module_function "$@"
}

# public entry fun borrow<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, dst_chain: u64, wormhole_message_fee: Coin<SUI>, amount: u64, ctx: &mut TxContext )
functions lending_portal_lending_borrow () {
    package_module_function "$@"
}

# public entry fun repay<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, repay_coin: Coin<CoinType>, ctx: &mut TxContext )
functions lending_portal_lending_repay () {
    package_module_function "$@"
}

# public entry fun liquidate<DebtCoinType, CollateralCoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, dst_chain: u64, wormhole_message_fee: Coin<SUI>, debt_pool: &mut Pool<DebtCoinType>, // liquidators repay debts to obtain collateral debt_coin: Coin<DebtCoinType>, collateral_pool: &mut Pool<CollateralCoinType>, // punished person punished: address, ctx: &mut TxContext )
functions lending_portal_lending_liquidate () {
    package_module_function "$@"
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
functions pool_manager_pool_manager_register_admin_cap () {
    package_module_function "$@"
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
functions lending_storage_register_admin_cap () {
    package_module_function "$@"
}

# public entry fun supply( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, storage: &mut Storage, vaa: vector<u8>, ctx: &mut TxContext )
functions lending_wormhole_adapter_supply () {
    package_module_function "$@"
}

# public entry fun withdraw( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, oracle: &mut PriceOracle, storage: &mut Storage, wormhole_message_fee: Coin<SUI>, vaa: vector<u8>, ctx: &mut TxContext )
functions lending_wormhole_adapter_withdraw () {
    package_module_function "$@"
}

# public entry fun borrow( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, oracle: &mut PriceOracle, storage: &mut Storage, wormhole_message_fee: Coin<SUI>, vaa: vector<u8>, ctx: &mut TxContext )
functions lending_wormhole_adapter_borrow () {
    package_module_function "$@"
}

# public entry fun repay( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, storage: &mut Storage, vaa: vector<u8>, ctx: &mut TxContext )
functions lending_wormhole_adapter_repay () {
    package_module_function "$@"
}

# public entry fun liquidate( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, oracle: &mut PriceOracle, storage: &mut Storage, wormhole_message_fee: Coin<SUI>, vaa: vector<u8>, ctx: &mut TxContext )
functions lending_wormhole_adapter_liquidate () {
    package_module_function "$@"
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
functions pool_manager_pool_manager_register_admin_cap () {
    package_module_function "$@"
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
functions lending_storage_register_admin_cap () {
    package_module_function "$@"
}

# public entry fun update_token_price( _: &OracleCap, price_oracle: &mut PriceOracle, token_name: vector<u8>, token_price: u64 )
functions oracle_oracle_update_token_price () {
    package_module_function "$@"
}

# public entry fun add_external_cap<T: store>( governance_external_cap: &mut GovernanceExternalCap, hash: vector<u8>, cap: T )
functions governance_governance_add_external_cap () {
    package_module_function "$@"
}

# public entry fun add_member(_: &GovernanceCap, goverance: &mut Governance, member: address)
functions governance_governance_add_member () {
    package_module_function "$@"
}

# public entry fun remove_member(_: &GovernanceCap, governance: &mut Governance, member: address)
functions governance_governance_remove_member () {
    package_module_function "$@"
}

# public entry fun create_proposal<T: key + store>(cap: T, ctx: &mut TxContext)
functions governance_governance_create_proposal () {
    package_module_function "$@"
}

# public entry fun create_vote<T: key + store>( gov: &mut Governance, vote_type: u8, proposal: &mut Proposal<T>, beneficiary: address, claim: bool, ctx: &mut TxContext )
functions governance_governance_create_vote () {
    package_module_function "$@"
}

# public entry fun vote_for_transfer<T: key + store>( gov: &mut Governance, proposal: &mut Proposal<T>, vote: &mut Vote<T>, ctx: &mut TxContext )
functions governance_governance_vote_for_transfer () {
    package_module_function "$@"
}

# public entry fun create_vote_external_cap( gov: &mut Governance, external_hash: vector<u8>, ctx: &mut TxContext )
functions governance_governance_create_vote_external_cap () {
    package_module_function "$@"
}

# public entry fun vote_for_approve<T: key + store>(gov: &mut Governance, vote: &mut Vote<T>, ctx: &mut TxContext)
functions governance_governance_vote_for_approve () {
    package_module_function "$@"
}

# public entry fun destroy_key<T>(key: Key<T>)
functions governance_governance_destroy_key () {
    package_module_function "$@"
}

# public entry fun vote_proposal( gov: &mut Governance, governance_external_cap: &mut GovernanceExternalCap, vote: &mut VoteExternalCap, core_state: &mut CoreState, ctx: &mut TxContext)
functions example_proposal_main_vote_proposal () {
    package_module_function "$@"
}

# public entry fun create_pool<CoinType>(ctx: &mut TxContext)
functions omnipool_pool_create_pool () {
    package_module_function "$@"
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
functions wormhole_bridge_bridge_pool_initialize_wormhole () {
    package_module_function "$@"
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
functions wormhole_bridge_bridge_core_initialize_wormhole () {
    package_module_function "$@"
}

# public entry fun register_remote_bridge( pool_state: &mut PoolState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_pool_register_remote_bridge () {
    package_module_function "$@"
}

# public entry fun register_remote_bridge( pool_state: &mut PoolState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_core_register_remote_bridge () {
    package_module_function "$@"
}

# public entry fun send_deposit<CoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, pool: &mut Pool<CoinType>, deposit_coin: Coin<CoinType>, app_id: u64, app_payload: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_pool_send_deposit () {
    package_module_function "$@"
}

# public entry fun send_withdraw<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, app_id: u64, app_payload: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_pool_send_withdraw () {
    package_module_function "$@"
}

# public entry fun send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, deposit_pool: &mut Pool<DepositCoinType>, deposit_coin: Coin<DepositCoinType>, withdraw_pool: &mut Pool<WithdrawCoinType>, withdraw_user: address, app_id: u64, app_payload: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_pool_send_deposit_and_withdraw () {
    package_module_function "$@"
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
functions wormhole_bridge_bridge_pool_initialize_wormhole () {
    package_module_function "$@"
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
functions wormhole_bridge_bridge_core_initialize_wormhole () {
    package_module_function "$@"
}

# public entry fun register_remote_bridge( core_state: &mut CoreState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_pool_register_remote_bridge () {
    package_module_function "$@"
}

# public entry fun register_remote_bridge( core_state: &mut CoreState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
functions wormhole_bridge_bridge_core_register_remote_bridge () {
    package_module_function "$@"
}

