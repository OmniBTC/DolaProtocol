// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

module governance_proposal::setup_governance_proposal {
    use std::option;

    use sui::tx_context::TxContext;

    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};

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

    public fun add_member(
        hot_potato: HotPotato,
        governance_info: &mut GovernanceInfo,
        member: address,
    ): HotPotato {
        governance_v1::add_member(&hot_potato.gov_cap, governance_info, member);

        hot_potato
    }

    public fun remove_member(
        hot_potato: HotPotato,
        governance_info: &mut GovernanceInfo,
        member: address,
    ): HotPotato {
        governance_v1::remove_member(&hot_potato.gov_cap, governance_info, member);

        hot_potato
    }
}
