module governance_actions::governance_actions {
    use std::ascii::string;
    use std::option;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::types::create_dola_address;
    use governance::governance::{Self, Governance, VoteExternalCap, GovernanceCap};
    use lending::storage::Storage;
    use lending::wormhole_adapter::WormholeAdapater;
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::tx_context::TxContext;
    use wormhole::state::State;
    use wormhole_bridge::bridge_core::{Self, CoreState};
    use wormhole_bridge::bridge_pool::{Self, PoolState};

    public entry fun vote_init_bridge_cap(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
        state: &mut State,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            bridge_core::initialize_wormhole_with_governance(governance_cap, state, ctx);
            bridge_pool::initialize_wormhole_with_governance(governance_cap, state, ctx);
        };

        governance::external_cap_destroy(vote, flash_cap);
    }

    public entry fun vote_init_lending_storage(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            let app_cap = app_manager::register_cap_with_governance(governance_cap, total_app_info, ctx);
            lending::storage::transfer_app_cap(storage, app_cap);
        };

        governance::external_cap_destroy(vote, flash_cap);
    }


    public entry fun vote_init_lending_wormhole_adapter(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
        wormhole_adapater: &mut WormholeAdapater,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            let storage_cap = lending::storage::register_cap_with_governance(governance_cap);
            lending::wormhole_adapter::transfer_storage_cap(wormhole_adapater, storage_cap);
        };

        governance::external_cap_destroy(vote, flash_cap);
    }

    public entry fun vote_register_core_remote_bridge(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
        core_state: &mut CoreState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            bridge_core::register_remote_bridge(governance_cap, core_state, emitter_chain_id, emitter_address, ctx);
        };

        governance::external_cap_destroy(vote, flash_cap);
    }

    public entry fun vote_register_pool_remote_bridge(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
        pool_state: &mut PoolState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            bridge_pool::register_remote_bridge(governance_cap, pool_state, emitter_chain_id, emitter_address, ctx);
        };

        governance::external_cap_destroy(vote, flash_cap);
    }


    public entry fun vote_register_new_pool(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            let pool_manager_cap = pool_manager::register_cap_with_governance(governance_cap);
            let pool = create_dola_address(pool_dola_chain_id, pool_dola_address);

            pool_manager::register_pool(
                &pool_manager_cap,
                pool_manager_info,
                pool,
                string(dola_pool_name),
                dola_pool_id,
                ctx
            );
        };

        governance::external_cap_destroy(vote, flash_cap);
    }

    public entry fun vote_register_new_reserve(
        gov: &mut Governance,
        vote: &mut VoteExternalCap,
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
        let flash_cap = governance::vote_external_cap<GovernanceCap>(gov, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let governance_cap = governance::borrow_external_cap(&mut flash_cap);
            let storage_cap = lending::storage::register_cap_with_governance(governance_cap);
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
        };

        governance::external_cap_destroy(vote, flash_cap);
    }
}
