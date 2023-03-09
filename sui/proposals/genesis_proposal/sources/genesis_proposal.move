module genesis_proposal::genesis_proposal {
    use std::ascii;
    use std::option;
    use std::vector;

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::dola_address::create_dola_address;
    use dola_types::dola_contract::DolaContractRegistry;
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use lending_core::storage::Storage;
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State;
    use wormhole_adapter_core::wormhole_adapter_core;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun vote_init_lending_core(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        wormhole_adapater: &mut lending_core::wormhole_adapter::WormholeAdapter,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            // init storage
            let app_cap = app_manager::register_cap_with_governance(&governance_cap, total_app_info, ctx);
            lending_core::storage::transfer_app_cap(storage, app_cap);

            // init wormhole adapter
            let storage_cap = lending_core::storage::register_cap_with_governance(&governance_cap);
            lending_core::wormhole_adapter::transfer_storage_cap(wormhole_adapater, storage_cap);

            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_init_system_core(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            // init storage
            system_core::storage::initialize_cap_with_governance(&governance_cap, total_app_info, ctx);

            // init wormhole adapter
            system_core::wormhole_adapter::initialize_cap_with_governance(&governance_cap, ctx);

            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_init_dola_portal(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        dola_contract_registry: &mut DolaContractRegistry,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            // init lending portal
            dola_portal::lending::initialize_cap_with_governance(&governance_cap, dola_contract_registry, ctx);

            // init system portal
            dola_portal::system::initialize_cap_with_governance(&governance_cap, ctx);

            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_init_chain_group_id(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        user_manager: &mut UserManagerInfo,
        group_id: u16,
        chain_ids: vector<u16>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let i = 0;
            while (i < vector::length(&chain_ids)) {
                let chain_id = *vector::borrow(&chain_ids, i);
                user_manager::register_dola_chain_id(&governance_cap, user_manager, chain_id, group_id);
                i = i + 1;
            };

            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_init_wormhole_adapter_core(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_state: &mut State,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            wormhole_adapter_core::initialize_cap_with_governance(&governance_cap, wormhole_state, ctx);

            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_register_new_pool(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        weight: u256,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);

            let pool = create_dola_address(pool_dola_chain_id, pool_dola_address);

            if (pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
                pool_manager::register_pool_id(
                    &governance_cap,
                    pool_manager_info,
                    ascii::string(dola_pool_name),
                    dola_pool_id,
                    ctx
                );
            };
            pool_manager::register_pool(&governance_cap, pool_manager_info, pool, dola_pool_id);
            pool_manager::set_pool_weight(&governance_cap, pool_manager_info, pool, weight);

            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_register_new_reserve(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        is_isolated_asset: bool,
        borrowable_in_isolation: bool,
        treasury: u64,
        treasury_factor: u256,
        borrow_cap_ceiling: u256,
        collateral_coefficient: u256,
        borrow_coefficient: u256,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let storage_cap = lending_core::storage::register_cap_with_governance(&governance_cap);
            lending_core::storage::register_new_reserve(
                &storage_cap,
                storage,
                oracle,
                dola_pool_id,
                is_isolated_asset,
                borrowable_in_isolation,
                treasury,
                treasury_factor,
                borrow_cap_ceiling,
                collateral_coefficient,
                borrow_coefficient,
                base_borrow_rate,
                borrow_rate_slope1,
                borrow_rate_slope2,
                optimal_utilization,
                ctx
            );
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }

    public entry fun vote_claim_from_treasury(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        pool_manager_info: &mut PoolManagerInfo,
        dola_pool_id: u16,
        dola_user_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);

        if (option::is_some(&governance_cap)) {
            let governance_cap = option::extract(&mut governance_cap);
            let storage_cap = lending_core::storage::register_cap_with_governance(&governance_cap);
            lending_core::logic::claim_from_treasury(
                &governance_cap,
                &storage_cap,
                pool_manager_info,
                storage,
                oracle,
                dola_pool_id,
                dola_user_id,
                (amount as u256)
            );
            governance_v1::destory_governance_cap(governance_cap);
        };

        option::destroy_none(governance_cap);
    }
}
