#!/bin/bash -f

. env.sh

# template
# module_function package module function args
function package_module_function() {
    args=($(get_args "$@"))
    sui client call --package "$package" --module "module" --function "function" --gas-budget 10000 --args "${args[@]}"
}

function get_args() {
    local args=""
    local i=0
    for arg in "$@"
    do
      args="$args $arg"
    done
    echo "$args"
}

# public entry fun supply<CoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, pool: &mut Pool<CoinType>, deposit_coin: Coin<CoinType>, ctx: &mut TxContext )
function lending_portal_lending_supply() {
    args=($(get_args "$@"))
    sui client call --package "$lending_portal" --module "lending" --function "supply<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun withdraw<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, dst_chain: u64, wormhole_message_fee: Coin<SUI>, amount: u64, ctx: &mut TxContext )
function lending_portal_lending_withdraw() {
    args=($(get_args "$@"))
    sui client call --package "$lending_portal" --module "lending" --function "withdraw<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun borrow<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, dst_chain: u64, wormhole_message_fee: Coin<SUI>, amount: u64, ctx: &mut TxContext )
function lending_portal_lending_borrow() {
    args=($(get_args "$@"))
    sui client call --package "$lending_portal" --module "lending" --function "borrow<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun repay<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, repay_coin: Coin<CoinType>, ctx: &mut TxContext )
function lending_portal_lending_repay() {
    args=($(get_args "$@"))
    sui client call --package "$lending_portal" --module "lending" --function "repay<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun liquidate<DebtCoinType, CollateralCoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, dst_chain: u64, wormhole_message_fee: Coin<SUI>, debt_pool: &mut Pool<DebtCoinType>, // liquidators repay debts to obtain collateral debt_coin: Coin<DebtCoinType>, collateral_pool: &mut Pool<CollateralCoinType>, // punished person punished: address, ctx: &mut TxContext )
function lending_portal_lending_liquidate() {
    args=($(get_args "$@"))
    sui client call --package "$lending_portal" --module "lending" --function "liquidate<DebtCoinType, CollateralCoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
function pool_manager_pool_manager_register_admin_cap() {
    args=($(get_args "$@"))
    sui client call --package "$pool_manager" --module "pool_manager" --function "register_admin_cap" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
function lending_storage_register_admin_cap() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "storage" --function "register_admin_cap" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun supply( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, storage: &mut Storage, vaa: vector<u8>, ctx: &mut TxContext )
function lending_wormhole_adapter_supply() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "wormhole_adapter" --function "supply" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun withdraw( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, oracle: &mut PriceOracle, storage: &mut Storage, wormhole_message_fee: Coin<SUI>, vaa: vector<u8>, ctx: &mut TxContext )
function lending_wormhole_adapter_withdraw() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "wormhole_adapter" --function "withdraw" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun borrow( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, oracle: &mut PriceOracle, storage: &mut Storage, wormhole_message_fee: Coin<SUI>, vaa: vector<u8>, ctx: &mut TxContext )
function lending_wormhole_adapter_borrow() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "wormhole_adapter" --function "borrow" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun repay( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, storage: &mut Storage, vaa: vector<u8>, ctx: &mut TxContext )
function lending_wormhole_adapter_repay() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "wormhole_adapter" --function "repay" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun liquidate( wormhole_adapter: &WormholeAdapater, pool_manager_info: &mut PoolManagerInfo, wormhole_state: &mut WormholeState, core_state: &mut CoreState, oracle: &mut PriceOracle, storage: &mut Storage, wormhole_message_fee: Coin<SUI>, vaa: vector<u8>, ctx: &mut TxContext )
function lending_wormhole_adapter_liquidate() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "wormhole_adapter" --function "liquidate" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
function pool_manager_pool_manager_register_admin_cap() {
    args=($(get_args "$@"))
    sui client call --package "$pool_manager" --module "pool_manager" --function "register_admin_cap" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_admin_cap(govern: &mut GovernanceExternalCap)
function lending_storage_register_admin_cap() {
    args=($(get_args "$@"))
    sui client call --package "$lending" --module "storage" --function "register_admin_cap" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun update_token_price( _: &OracleCap, price_oracle: &mut PriceOracle, token_name: vector<u8>, token_price: u64 )
function oracle_oracle_update_token_price() {
    args=($(get_args "$@"))
    sui client call --package "$oracle" --module "oracle" --function "update_token_price" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun add_external_cap<T: store>( governance_external_cap: &mut GovernanceExternalCap, hash: vector<u8>, cap: T )
function governance_governance_add_external_cap() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "add_external_cap<T: store>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun add_member(_: &GovernanceCap, goverance: &mut Governance, member: address)
function governance_governance_add_member() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "add_member" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun remove_member(_: &GovernanceCap, governance: &mut Governance, member: address)
function governance_governance_remove_member() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "remove_member" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun create_proposal<T: key + store>(cap: T, ctx: &mut TxContext)
function governance_governance_create_proposal() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "create_proposal<T: key + store>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun create_vote<T: key + store>( gov: &mut Governance, vote_type: u8, proposal: &mut Proposal<T>, beneficiary: address, claim: bool, ctx: &mut TxContext )
function governance_governance_create_vote() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "create_vote<T: key + store>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun vote_for_transfer<T: key + store>( gov: &mut Governance, proposal: &mut Proposal<T>, vote: &mut Vote<T>, ctx: &mut TxContext )
function governance_governance_vote_for_transfer() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "vote_for_transfer<T: key + store>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun create_vote_external_cap( gov: &mut Governance, external_hash: vector<u8>, ctx: &mut TxContext )
function governance_governance_create_vote_external_cap() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "create_vote_external_cap" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun vote_for_approve<T: key + store>(gov: &mut Governance, vote: &mut Vote<T>, ctx: &mut TxContext)
function governance_governance_vote_for_approve() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "vote_for_approve<T: key + store>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun destroy_key<T>(key: Key<T>)
function governance_governance_destroy_key() {
    args=($(get_args "$@"))
    sui client call --package "$governance" --module "governance" --function "destroy_key<T>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun vote_proposal( gov: &mut Governance, governance_external_cap: &mut GovernanceExternalCap, vote: &mut VoteExternalCap, core_state: &mut CoreState, ctx: &mut TxContext)
function example_proposal_main_vote_proposal() {
    args=($(get_args "$@"))
    sui client call --package "$example_proposal" --module "main" --function "vote_proposal" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun create_pool<CoinType>(ctx: &mut TxContext)
function omnipool_pool_create_pool() {
    args=($(get_args "$@"))
    sui client call --package "$omnipool" --module "pool" --function "create_pool<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
function wormhole_bridge_bridge_pool_initialize_wormhole() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "initialize_wormhole" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
function wormhole_bridge_bridge_core_initialize_wormhole() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_core" --function "initialize_wormhole" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_remote_bridge( pool_state: &mut PoolState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_pool_register_remote_bridge() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "register_remote_bridge" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_remote_bridge( pool_state: &mut PoolState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_core_register_remote_bridge() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_core" --function "register_remote_bridge" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun send_deposit<CoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, pool: &mut Pool<CoinType>, deposit_coin: Coin<CoinType>, app_id: u64, app_payload: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_pool_send_deposit() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "send_deposit<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun send_withdraw<CoinType>( pool: &mut Pool<CoinType>, pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, app_id: u64, app_payload: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_pool_send_withdraw() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "send_withdraw<CoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>( pool_state: &mut PoolState, wormhole_state: &mut WormholeState, wormhole_message_fee: Coin<SUI>, deposit_pool: &mut Pool<DepositCoinType>, deposit_coin: Coin<DepositCoinType>, withdraw_pool: &mut Pool<WithdrawCoinType>, withdraw_user: address, app_id: u64, app_payload: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_pool_send_deposit_and_withdraw() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
function wormhole_bridge_bridge_pool_initialize_wormhole() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "initialize_wormhole" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
function wormhole_bridge_bridge_core_initialize_wormhole() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_core" --function "initialize_wormhole" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_remote_bridge( core_state: &mut CoreState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_pool_register_remote_bridge() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_pool" --function "register_remote_bridge" --gas-budget 10000 --args "${args[@]}" 
}

# public entry fun register_remote_bridge( core_state: &mut CoreState, emitter_chain_id: u64, emitter_address: vector<u8>, ctx: &mut TxContext )
function wormhole_bridge_bridge_core_register_remote_bridge() {
    args=($(get_args "$@"))
    sui client call --package "$wormhole_bridge" --module "bridge_core" --function "register_remote_bridge" --gas-budget 10000 --args "${args[@]}" 
}

