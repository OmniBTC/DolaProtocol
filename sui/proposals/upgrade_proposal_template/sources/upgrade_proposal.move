module upgrade_proposal_template::upgrade_proposal {
    use std::option;

    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::package::{UpgradeTicket, UpgradeReceipt};
    use sui::tx_context::TxContext;

    /// The digest of the new contract
    const DIGEST: vector<u8> = x"16ea59a7d86f056989cb4cfd5e01e7989111b930d5ee0eb9f7a67cc8c4f75dd3";
    const POLICY: u8 = 0;

    /// Errors
    const ENOT_FINAL_VOTE: u64 = 0;

    const EIS_FINAL_VOTE: u64 = 0;

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

    public fun vote_proposal_final(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        gov_genesis: &mut GovernanceGenesis,
        ctx: &mut TxContext
    ): UpgradeTicket {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_some(&governance_cap), ENOT_FINAL_VOTE);
        let cap = option::extract(&mut governance_cap);
        let ticket = genesis::authorize_upgrade(&cap, gov_genesis, POLICY, DIGEST);
        governance_v1::destroy_governance_cap(cap);
        option::destroy_none(governance_cap);
        ticket
    }

    public fun commit_upgrade(
        gov_genesis: &mut GovernanceGenesis,
        receipt: UpgradeReceipt,
    ) {
        genesis::commit_upgrade(gov_genesis, receipt)
    }
}
