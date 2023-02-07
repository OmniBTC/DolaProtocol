module governance_actions::governance_actions {
    use std::ascii::string;
    use std::option;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::types::create_dola_address;
    use governance::genesis;
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use lending::storage::Storage;
    use lending::wormhole_adapter::WormholeAdapater;
    use lending_portal::lending::LendingPortal;
    use omnipool::pool;
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State;
    use wormhole_bridge::bridge_core::{Self, CoreState};
    use wormhole_bridge::bridge_pool::{Self, PoolState};

    public entry fun vote_init_bridge_cap(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        state: &mut State,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            bridge_core::initialize_wormhole_with_governance(&governance_cap, state, ctx);
            bridge_pool::initialize_wormhole_with_governance(&governance_cap, state, ctx);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }

    public entry fun vote_init_lending_storage(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let app_cap = app_manager::register_cap_with_governance(&governance_cap, total_app_info, ctx);
            lending::storage::transfer_app_cap(storage, app_cap);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }


    public entry fun vote_init_lending_wormhole_adapter(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        wormhole_adapater: &mut WormholeAdapater,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let storage_cap = lending::storage::register_cap_with_governance(&governance_cap);
            lending::wormhole_adapter::transfer_storage_cap(wormhole_adapater, storage_cap);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }

    public entry fun vote_init_lending_portal(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        lending_portal: &mut LendingPortal,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let pool_cap = pool::register_cap(&governance_cap, ctx);
            let storage_cap = lending::storage::register_cap_with_governance(&governance_cap);
            let pool_manager_cap = pool_manager::pool_manager::register_cap_with_governance(&governance_cap);
            let user_manager_cap = user_manager::user_manager::register_cap_with_governance(&governance_cap);
            lending_portal::lending::transfer_pool_cap(lending_portal, pool_cap);
            lending_portal::lending::transfer_storage_cap(lending_portal, storage_cap);
            lending_portal::lending::transfer_pool_manager_cap(lending_portal, pool_manager_cap);
            lending_portal::lending::transfer_user_manager_cap(lending_portal, user_manager_cap);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }

    public entry fun vote_register_evm_chain_id(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        user_manager: &mut UserManagerInfo,
        evm_chain_id: u16,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let user_manager_cap = user_manager::register_cap_with_governance(&governance_cap);
            // todo: chain id should be fixed, initializing multiple evm_chain_id according to the actual situation
            user_manager::register_evm_chain_id(&user_manager_cap, user_manager, evm_chain_id);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }

    public entry fun vote_register_core_remote_bridge(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        core_state: &mut CoreState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            bridge_core::register_remote_bridge(&governance_cap, core_state, emitter_chain_id, emitter_address, ctx);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }

    public entry fun vote_register_pool_remote_bridge(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        pool_state: &mut PoolState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            bridge_pool::register_remote_bridge(&governance_cap, pool_state, emitter_chain_id, emitter_address, ctx);
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }


    public entry fun vote_register_new_pool(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let pool_manager_cap = pool_manager::register_cap_with_governance(&governance_cap);
            let pool = create_dola_address(pool_dola_chain_id, pool_dola_address);

            pool_manager::register_pool(
                &pool_manager_cap,
                pool_manager_info,
                pool,
                string(dola_pool_name),
                dola_pool_id,
                ctx
            );
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }

    public entry fun vote_register_new_reserve(
        gov_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        treasury: u64,
        treasury_factor: u64,
        collateral_coefficient: u64,
        borrow_coefficient: u64,
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_external_cap(gov_info, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let storage_cap = lending::storage::register_cap_with_governance(&governance_cap);
            lending::storage::register_new_reserve(
                &storage_cap,
                storage,
                oracle,
                dola_pool_id,
                treasury,
                treasury_factor,
                collateral_coefficient,
                borrow_coefficient,
                base_borrow_rate,
                borrow_rate_slope1,
                borrow_rate_slope2,
                optimal_utilization,
                ctx
            );
            genesis::destroy(governance_cap);
        };

        option::destroy_none(governance_cap)
    }
}
