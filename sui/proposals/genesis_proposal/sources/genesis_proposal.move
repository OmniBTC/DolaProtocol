// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Note: publish with immutable
module genesis_proposal::genesis_proposal {
    use std::ascii;
    use std::option::{Self, Option};
    use std::vector;

    use app_manager::app_manager::TotalAppInfo;
    use dola_types::dola_address;
    use dola_types::dola_contract::DolaContractRegistry;
    use governance::genesis::{GovernanceContracts, GovernanceCap};
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use lending_core::storage::Storage;
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::package::UpgradeCap;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State;
    use wormhole_adapter_core::wormhole_adapter_core::{Self, CoreState};

    const E_FINISHED_PROPOSAL: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    struct ProposalInfo has key {
        id: UID,
        proposal_num: u64,
        proposal_cap: Option<GovernanceCap>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(ProposalInfo {
            id: object::new(ctx),
            // Determine the number of times the function is to be executed,
            // completing the entire proposal in one programmable transaction.
            proposal_num: 14,
            proposal_cap: option::none()
        })
    }

    fun get_proposal_cap(proposal_info: &mut ProposalInfo): &GovernanceCap {
        proposal_info.proposal_num = proposal_info.proposal_num - 1;
        assert!(proposal_info.proposal_num > 0, E_FINISHED_PROPOSAL);
        option::borrow(&proposal_info.proposal_cap)
    }

    fun destroy_cap(proposal_info: &mut ProposalInfo) {
        if (proposal_info.proposal_num == 0) {
            let proposal_cap = option::extract(&mut proposal_info.proposal_cap);
            governance_v1::destroy_governance_cap(proposal_cap);
        }
    }

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun vote_porposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        proposal_info: &mut ProposalInfo,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            option::fill(&mut proposal_info.proposal_cap, cap);
        };
        option::destroy_none(governance_cap)
    }

    public entry fun init_lending_core(
        proposal_info: &mut ProposalInfo,
        dola_contract_registry: &mut DolaContractRegistry,
        gov_contracts: &mut GovernanceContracts,
        total_app_info: &mut TotalAppInfo,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        // init storage
        lending_core::storage::initialize_cap_with_governance(governance_cap, total_app_info, ctx);

        // init wormhole adapter
        lending_core::wormhole_adapter::initialize_cap_with_governance(
            governance_cap,
            gov_contracts,
            dola_contract_registry,
            upgrade_cap,
            ctx
        );

        destroy_cap(proposal_info);
    }

    public entry fun init_system_core(
        proposal_info: &mut ProposalInfo,
        total_app_info: &mut TotalAppInfo,
        gov_contracts: &mut GovernanceContracts,
        dola_registry: &mut DolaContractRegistry,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        // init storage
        system_core::storage::initialize_cap_with_governance(governance_cap, total_app_info, ctx);

        // init wormhole adapter
        system_core::wormhole_adapter::initialize_cap_with_governance(
            governance_cap,
            gov_contracts,
            dola_registry,
            upgrade_cap,
            ctx
        );

        destroy_cap(proposal_info);
    }

    public entry fun init_dola_portal(
        proposal_info: &mut ProposalInfo,
        gov_contracts: &mut GovernanceContracts,
        dola_contract_registry: &mut DolaContractRegistry,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        // init lending portal
        dola_portal::lending::initialize_cap_with_governance(
            governance_cap,
            gov_contracts,
            dola_contract_registry,
            upgrade_cap,
            ctx
        );

        // init system portal
        dola_portal::system::initialize_cap_with_governance(governance_cap, ctx);

        destroy_cap(proposal_info);
    }

    public entry fun init_chain_group_id(
        proposal_info: &mut ProposalInfo,
        user_manager: &mut UserManagerInfo,
        group_id: u16,
        chain_ids: vector<u16>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        let i = 0;
        while (i < vector::length(&chain_ids)) {
            let chain_id = *vector::borrow(&chain_ids, i);
            user_manager::register_dola_chain_id(governance_cap, user_manager, chain_id, group_id);
            i = i + 1;
        };

        destroy_cap(proposal_info);
    }

    public entry fun init_wormhole_adapter_core(
        proposal_info: &mut ProposalInfo,
        gov_contracts: &mut GovernanceContracts,
        dola_contract_registry: &mut DolaContractRegistry,
        wormhole_state: &mut State,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::initialize_cap_with_governance(
            governance_cap,
            wormhole_state,
            gov_contracts,
            dola_contract_registry,
            upgrade_cap,
            ctx
        );

        destroy_cap(proposal_info);
    }

    public entry fun register_new_pool(
        proposal_info: &mut ProposalInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        weight: u256,
        ctx: &mut TxContext
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        let pool = dola_address::create_dola_address(pool_dola_chain_id, pool_dola_address);

        if (!pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
            pool_manager::register_pool_id(
                governance_cap,
                pool_manager_info,
                ascii::string(dola_pool_name),
                dola_pool_id,
                ctx
            );
        };
        pool_manager::register_pool(governance_cap, pool_manager_info, pool, dola_pool_id);
        pool_manager::set_pool_weight(governance_cap, pool_manager_info, pool, weight);

        destroy_cap(proposal_info);
    }


    public entry fun register_new_reserve(
        proposal_info: &mut ProposalInfo,
        clock: &Clock,
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
        let governance_cap = get_proposal_cap(proposal_info);
        let storage_cap = lending_core::storage::register_cap_with_governance(governance_cap);
        lending_core::storage::register_new_reserve(
            &storage_cap,
            storage,
            clock,
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

        destroy_cap(proposal_info);
    }

    public entry fun register_remote_bridge(
        proposal_info: &mut ProposalInfo,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::register_remote_bridge(
            governance_cap,
            core_state,
            wormhole_emitter_chain,
            wormhole_emitter_address
        );

        destroy_cap(proposal_info);
    }

    public entry fun delete_remote_bridge(
        proposal_info: &mut ProposalInfo,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::delete_remote_bridge(
            governance_cap,
            core_state,
            wormhole_emitter_chain
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_register_owner(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);
        wormhole_adapter_core::remote_register_owner(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_register_spender(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::remote_register_spender(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_delete_owner(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::remote_delete_owner(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_delete_spender(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::remote_delete_spender(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }
}
