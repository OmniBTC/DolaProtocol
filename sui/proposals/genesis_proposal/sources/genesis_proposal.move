// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

module genesis_proposal::genesis_proposal {
    use std::ascii;
    use std::option;
    use std::vector;

    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;

    use dola_protocol::app_manager::TotalAppInfo;
    use dola_protocol::dola_address;
    use dola_protocol::dola_pool;
    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use dola_protocol::lending_core_storage::{Self, Storage};
    use dola_protocol::lending_logic;
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::system_core_storage;
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::wormhole_adapter_core::{Self, CoreState};
    use wormhole::state::State;

    const EIS_FINAL_VOTE: u64 = 0;

    const EUNFINISHED_VOTE: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal<Certificate>(governance_info, Certificate {}, ctx)
    }

    public fun vote_porposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_none(&governance_cap), EIS_FINAL_VOTE);
        option::destroy_none(governance_cap)
    }

    public fun vote_proposal_final(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_some(&governance_cap), EUNFINISHED_VOTE);
        let cap = option::extract(&mut governance_cap);
        option::destroy_none(governance_cap);
        (cap, Certificate {})
    }

    /// Call when the proposal is complete
    public fun destory(governance_cap: GovernanceCap, certificate: Certificate) {
        governance_v1::destroy_governance_cap(governance_cap);
        let Certificate {} = certificate;
    }

    public fun init_lending_core(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        // init storage
        lending_core_storage::initialize_cap_with_governance(&governance_cap, total_app_info, ctx);

        (governance_cap, certificate)
    }

    public fun init_system_core(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        // init storage
        system_core_storage::initialize_cap_with_governance(&governance_cap, total_app_info, ctx);

        (governance_cap, certificate)
    }

    public fun init_chain_group_id(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        user_manager: &mut UserManagerInfo,
        group_id: u16,
        chain_ids: vector<u16>,
    ): (GovernanceCap, Certificate) {
        let i = 0;
        while (i < vector::length(&chain_ids)) {
            let chain_id = *vector::borrow(&chain_ids, i);
            user_manager::register_dola_chain_id(&governance_cap, user_manager, chain_id, group_id);
            i = i + 1;
        };
        (governance_cap, certificate)
    }

    public fun init_wormhole_adapter_core(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        wormhole_state: &mut State,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::initialize_cap_with_governance(&governance_cap, wormhole_state, ctx);
        (governance_cap, certificate)
    }

    public fun register_new_pool(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        weight: u256,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        let pool = dola_address::create_dola_address(pool_dola_chain_id, pool_dola_address);

        if (!pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
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
        (governance_cap, certificate)
    }

    public fun register_remote_bridge(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>,
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::register_remote_bridge(
            &governance_cap,
            core_state,
            wormhole_emitter_chain,
            wormhole_emitter_address
        );
        (governance_cap, certificate)
    }

    public fun delete_remote_bridge(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::delete_remote_bridge(
            &governance_cap,
            core_state,
            wormhole_emitter_chain
        );

        (governance_cap, certificate)
    }

    public fun remote_register_owner(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::remote_register_owner(
            &governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee,
            clock
        );
        (governance_cap, certificate)
    }

    public fun remote_register_spender(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::remote_register_spender(
            &governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee,
            clock
        );
        (governance_cap, certificate)
    }

    public fun remote_delete_owner(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::remote_delete_owner(
            &governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee,
            clock
        );
        (governance_cap, certificate)
    }

    public fun remote_delete_spender(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): (GovernanceCap, Certificate) {
        wormhole_adapter_core::remote_delete_spender(
            &governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee,
            clock
        );
        (governance_cap, certificate)
    }

    public fun create_omnipool<CoinType>(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        decimals: u8,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        dola_pool::create_pool<CoinType>(&governance_cap, decimals, ctx);
        (governance_cap, certificate)
    }

    public fun register_new_reserve(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
        is_isolated_asset: bool,
        borrowable_in_isolation: bool,
        treasury: u64,
        treasury_factor: u256,
        supply_cap_ceiling: u256,
        borrow_cap_ceiling: u256,
        collateral_coefficient: u256,
        borrow_coefficient: u256,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256,
        ctx: &mut TxContext
    ): (GovernanceCap, Certificate) {
        lending_core_storage::register_new_reserve(
            &governance_cap,
            storage,
            clock,
            dola_pool_id,
            is_isolated_asset,
            borrowable_in_isolation,
            treasury,
            treasury_factor,
            supply_cap_ceiling,
            borrow_cap_ceiling,
            collateral_coefficient,
            borrow_coefficient,
            base_borrow_rate,
            borrow_rate_slope1,
            borrow_rate_slope2,
            optimal_utilization,
            ctx
        );
        (governance_cap, certificate)
    }

    public fun claim_from_treasury(
        governance_cap: GovernanceCap,
        certificate: Certificate,
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
        dola_user_id: u64,
        amount: u64,
    ): (GovernanceCap, Certificate) {
        lending_logic::claim_from_treasury(
            &governance_cap,
            pool_manager_info,
            storage,
            clock,
            dola_pool_id,
            dola_user_id,
            (amount as u256)
        );
        (governance_cap, certificate)
    }
}
