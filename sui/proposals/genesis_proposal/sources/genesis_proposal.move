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
    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use dola_protocol::lending_core_storage::{Self, Storage};
    use dola_protocol::lending_logic;
    use dola_protocol::oracle::{Self, PriceOracle};
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::system_core_storage;
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use dola_protocol::wormhole_adapter_core::{Self, CoreState};
    use dola_protocol::wormhole_adapter_pool;
    use dola_protocol::wormhole_adapter_pool::PoolState;
    use wormhole::state::State;
    use dola_protocol::boost;
    use dola_protocol::boost::RewardPool;
    use sui::transfer;

    const EIS_FINAL_VOTE: u64 = 0;

    const EUNFINISHED_VOTE: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    /// Ensure that gov_cap is only used for the current contract and must be destroyed when it is finished.
    struct HotPotato {
        gov_cap: GovernanceCap
    }

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal_with_history<Certificate>(governance_info, Certificate {}, ctx)
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
    ): HotPotato {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_some(&governance_cap), EUNFINISHED_VOTE);
        let gov_cap = option::extract(&mut governance_cap);
        option::destroy_none(governance_cap);
        HotPotato { gov_cap }
    }

    /// Call when the proposal is complete
    public fun destory(hot_potato: HotPotato) {
        let HotPotato { gov_cap } = hot_potato;
        governance_v1::destroy_governance_cap(gov_cap);
    }

    public fun init_lending_core(
        hot_potato: HotPotato,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): HotPotato {
        // init storage
        lending_core_storage::initialize_cap_with_governance(&hot_potato.gov_cap, total_app_info, ctx);

        hot_potato
    }

    public fun init_system_core(
        hot_potato: HotPotato,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): HotPotato {
        // init storage
        system_core_storage::initialize_cap_with_governance(&hot_potato.gov_cap, total_app_info, ctx);

        hot_potato
    }

    public fun init_chain_group_id(
        hot_potato: HotPotato,
        user_manager: &mut UserManagerInfo,
        group_id: u16,
        chain_ids: vector<u16>,
    ): HotPotato {
        let i = 0;
        while (i < vector::length(&chain_ids)) {
            let chain_id = *vector::borrow(&chain_ids, i);
            user_manager::register_dola_chain_id(&hot_potato.gov_cap, user_manager, chain_id, group_id);
            i = i + 1;
        };
        hot_potato
    }

    public fun init_wormhole_adapter_core(
        hot_potato: HotPotato,
        wormhole_state: &mut State,
        ctx: &mut TxContext
    ): HotPotato {
        wormhole_adapter_core::initialize_cap_with_governance(&hot_potato.gov_cap, wormhole_state, ctx);
        hot_potato
    }

    public fun register_token_price(
        hot_potato: HotPotato,
        price_oracle: &mut PriceOracle,
        dola_pool_id: u16,
        feed_id: vector<u8>,
        price_value: u256,
        price_decimal: u8,
        clock: &Clock
    ): HotPotato {
        oracle::register_token_price(
            &hot_potato.gov_cap,
            price_oracle,
            feed_id,
            dola_pool_id,
            price_value,
            price_decimal,
            clock
        );
        hot_potato
    }

    public fun register_new_pool(
        hot_potato: HotPotato,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        weight: u256,
        ctx: &mut TxContext
    ): HotPotato {
        let pool = dola_address::create_dola_address(pool_dola_chain_id, pool_dola_address);

        if (!pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
            pool_manager::register_pool_id(
                &hot_potato.gov_cap,
                pool_manager_info,
                ascii::string(dola_pool_name),
                dola_pool_id,
                ctx
            );
        };
        pool_manager::register_pool(&hot_potato.gov_cap, pool_manager_info, pool, dola_pool_id);
        pool_manager::set_pool_weight(&hot_potato.gov_cap, pool_manager_info, pool, weight);
        hot_potato
    }

    public fun register_remote_bridge(
        hot_potato: HotPotato,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>,
    ): HotPotato {
        wormhole_adapter_core::register_remote_bridge(
            &hot_potato.gov_cap,
            core_state,
            wormhole_emitter_chain,
            wormhole_emitter_address
        );
        hot_potato
    }

    public fun delete_remote_bridge(
        hot_potato: HotPotato,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
    ): HotPotato {
        wormhole_adapter_core::delete_remote_bridge(
            &hot_potato.gov_cap,
            core_state,
            wormhole_emitter_chain
        );

        hot_potato
    }

    public fun remote_register_spender(
        hot_potato: HotPotato,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): HotPotato {
        wormhole_adapter_core::remote_register_spender(
            &hot_potato.gov_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee,
            clock
        );
        hot_potato
    }

    public fun remote_delete_spender(
        hot_potato: HotPotato,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): HotPotato {
        wormhole_adapter_core::remote_delete_spender(
            &hot_potato.gov_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee,
            clock
        );
        hot_potato
    }

    public fun register_new_reserve(
        hot_potato: HotPotato,
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
    ): HotPotato {
        lending_core_storage::register_new_reserve(
            &hot_potato.gov_cap,
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
        hot_potato
    }

    public fun claim_from_treasury(
        hot_potato: HotPotato,
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
        dola_user_id: u64,
        amount: u64,
    ): HotPotato {
        lending_logic::claim_from_treasury(
            &hot_potato.gov_cap,
            pool_manager_info,
            storage,
            clock,
            dola_pool_id,
            dola_user_id,
            (amount as u256)
        );
        hot_potato
    }

    public fun add_pool_relayer(
        hot_potato: HotPotato,
        pool_state: &mut PoolState,
        relayer: address
    ): HotPotato {
        wormhole_adapter_pool::add_relayer(
            &hot_potato.gov_cap,
            pool_state,
            relayer
        );
        hot_potato
    }

    public fun remove_pool_relayer(
        hot_potato: HotPotato,
        pool_state: &mut PoolState,
        relayer: address
    ): HotPotato {
        wormhole_adapter_pool::remove_relayer(
            &hot_potato.gov_cap,
            pool_state,
            relayer
        );
        hot_potato
    }

    public fun add_core_relayer(
        hot_potato: HotPotato,
        core_state: &mut CoreState,
        relayer: address
    ): HotPotato {
        wormhole_adapter_core::add_relayer(
            &hot_potato.gov_cap,
            core_state,
            relayer
        );
        hot_potato
    }

    public fun remove_core_relayer(
        hot_potato: HotPotato,
        core_state: &mut CoreState,
        relayer: address
    ): HotPotato {
        wormhole_adapter_core::remove_relayer(
            &hot_potato.gov_cap,
            core_state,
            relayer
        );
        hot_potato
    }

    public fun add_oracle_relayer(
        hot_potato: HotPotato,
        price_oracle: &mut PriceOracle,
        relayer: address
    ): HotPotato {
        oracle::add_relayer(
            &hot_potato.gov_cap,
            price_oracle,
            relayer
        );
        hot_potato
    }

    public fun remove_oracle_relayer(
        hot_potato: HotPotato,
        price_oracle: &mut PriceOracle,
        relayer: address
    ): HotPotato {
        oracle::remove_relayer(
            &hot_potato.gov_cap,
            price_oracle,
            relayer
        );
        hot_potato
    }

    public fun remote_add_relayer(
        hot_potato: HotPotato,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        relayer: vector<u8>,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): HotPotato {
        wormhole_adapter_core::remote_add_relayer(
            &hot_potato.gov_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            relayer,
            wormhole_message_fee,
            clock
        );
        hot_potato
    }

    public fun remote_remove_relayer(
        hot_potato: HotPotato,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        relayer: vector<u8>,
        wormhole_message_fee: Coin<SUI>,
        clock: &Clock,
    ): HotPotato {
        wormhole_adapter_core::remote_remove_relayer(
            &hot_potato.gov_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            relayer,
            wormhole_message_fee,
            clock
        );
        hot_potato
    }

    public fun create_reward_pool<X>(
        hot_potato: HotPotato,
        storage: &mut Storage,
        start_time: u256,
        end_time: u256,
        reward: Coin<X>,
        dola_pool_id: u16,
        reward_action: u8,
        ctx: &mut TxContext
    ): HotPotato {
        boost::create_reward_pool<X>(
            &hot_potato.gov_cap,
            storage,
            start_time,
            end_time,
            reward,
            dola_pool_id,
            reward_action,
            ctx
        );
        hot_potato
    }

    public fun remove_reward_pool<X>(
        hot_potato: HotPotato,
        storage: &mut Storage,
        reward_pool_balance: &mut RewardPool<X>,
        dola_pool_id: u16,
        refund_address: address,
        ctx: &mut TxContext
    ): HotPotato {
        let refund = boost::remove_reward_pool<X>(
            &hot_potato.gov_cap,
            storage,
            reward_pool_balance,
            dola_pool_id,
            ctx
        );
        transfer::public_transfer(refund, refund_address);
        hot_potato
    }
}
