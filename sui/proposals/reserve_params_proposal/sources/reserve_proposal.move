// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

module reserve_proposal::reserve_proposal {
    use std::option;

    use sui::tx_context::TxContext;

    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use dola_protocol::lending_core_storage::{Self, Storage};

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

    public fun set_is_isolated_asset(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        is_isolated_asset: bool
    ): HotPotato {
        lending_core_storage::set_is_isolated_asset(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            is_isolated_asset
        );
        hot_potato
    }

    public fun set_borrowable_in_isolation(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        borrowable_in_isolation: bool
    ): HotPotato {
        lending_core_storage::set_borrowable_in_isolation(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            borrowable_in_isolation
        );
        hot_potato
    }

    public fun set_treasury_factor(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        treasury_factor: u256
    ): HotPotato {
        lending_core_storage::set_treasury_factor(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            treasury_factor
        );
        hot_potato
    }

    public fun set_supply_cap_ceiling(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        supply_cap_ceiling: u256
    ): HotPotato {
        lending_core_storage::set_supply_cap_ceiling(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            supply_cap_ceiling
        );
        hot_potato
    }

    public fun set_borrow_cap_ceiling(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        borrow_cap_ceiling: u256
    ): HotPotato {
        lending_core_storage::set_borrow_cap_ceiling(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            borrow_cap_ceiling
        );
        hot_potato
    }

    public fun set_collateral_coefficient(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        collateral_coefficient: u256
    ): HotPotato {
        lending_core_storage::set_collateral_coefficient(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            collateral_coefficient
        );
        hot_potato
    }

    public fun set_borrow_coefficient(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        borrow_coefficient: u256
    ): HotPotato {
        lending_core_storage::set_borrow_coefficient(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            borrow_coefficient
        );
        hot_potato
    }

    public fun set_borrow_rate_factors(
        hot_potato: HotPotato,
        storage: &mut Storage,
        dola_pool_id: u16,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256
    ): HotPotato {
        lending_core_storage::set_borrow_rate_factors(
            &hot_potato.gov_cap,
            storage,
            dola_pool_id,
            base_borrow_rate,
            borrow_rate_slope1,
            borrow_rate_slope2,
            optimal_utilization
        );
        hot_potato
    }
}
