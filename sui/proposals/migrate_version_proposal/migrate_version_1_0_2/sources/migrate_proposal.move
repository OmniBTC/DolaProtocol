module migrate_version_proposal::migrate_proposal {
    use std::option;

    use dola_protocol::genesis::{Self, GovernanceGenesis, Version_1_0_2, Version_1_0_3};
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::tx_context::TxContext;

    /// Errors
    const ENOT_FINAL_VOTE: u64 = 0;

    const EIS_FINAL_VOTE: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun vote_porposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_none(&governance_cap), EIS_FINAL_VOTE);
        option::destroy_none(governance_cap)
    }

    public fun migrate_version(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        gov_genesis: &mut GovernanceGenesis,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_some(&governance_cap), ENOT_FINAL_VOTE);
        let cap = option::extract(&mut governance_cap);
        let new_version = genesis::get_version_1_0_3();
        genesis::migrate_version<Version_1_0_2, Version_1_0_3>(&cap, gov_genesis, new_version);
        governance_v1::destroy_governance_cap(cap);
        option::destroy_none(governance_cap);
    }
}
