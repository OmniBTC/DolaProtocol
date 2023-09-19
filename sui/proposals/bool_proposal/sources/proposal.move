module bool_proposal::proposal {
    use std::option;
    use sui::tx_context::TxContext;

    use boolamt::anchor::{GlobalState, AnchorCap};

    use dola_protocol::genesis::GovernanceCap;
    use dola_protocol::governance_v1::{ Self, GovernanceInfo, Proposal };
    use dola_protocol::bool_adapter_core::{
        register_path, set_anchor_cap, release_anchor_cap, CoreState
    };


    const EIS_FINAL_VOTE: u64 = 0;

    const EUNFINISHED_VOTE: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    /// Ensure that gov_cap is only used for the current contract and must be destroyed when it is finished.
    struct HotPotato {
        gov_cap: GovernanceCap
    }

    public entry fun create_proposal(
        governance_info: &mut GovernanceInfo,
        ctx: &mut TxContext
    ) {
        governance_v1::create_proposal_with_history<Certificate>(
            governance_info,
            Certificate {},
            ctx
        )
    }

    public fun vote_porposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(
            governance_info, Certificate {},
            proposal,
            true,
            ctx
        );

        assert!(option::is_none(&governance_cap), EIS_FINAL_VOTE);

        option::destroy_none(governance_cap)
    }

    public fun vote_proposal_final(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ): HotPotato {
        let governance_cap = governance_v1::vote_proposal(
            governance_info,
            Certificate {},
            proposal,
            true,
            ctx
        );

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

    public fun bool_register_path(
        hot_potato: HotPotato,
        bool_core_state: &mut CoreState,
        dola_chain_id: u16,
        dst_chain_id: u32,
        dst_anchor: address,
        bool_global_state: &mut GlobalState,
    ): HotPotato {
        register_path(
            &hot_potato.gov_cap,
            bool_core_state,
            dola_chain_id,
            dst_chain_id,
            dst_anchor,
            bool_global_state
        );

        hot_potato
    }

    public fun bool_set_anchor_cap(
        hot_potato: HotPotato,
        core_state: &mut CoreState,
        bool_anchor_cap: AnchorCap
    ): HotPotato {
        set_anchor_cap(
            &hot_potato.gov_cap,
            core_state,
            bool_anchor_cap
        );

        hot_potato
    }

    public fun bool_release_anchor_cap(
        hot_potato: HotPotato,
        core_state: &mut CoreState,
        receiver: address
    ): HotPotato {
        release_anchor_cap(
            &hot_potato.gov_cap,
            core_state,
            receiver
        );

        hot_potato
    }
}
