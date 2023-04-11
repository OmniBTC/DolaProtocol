module upgrade_proposal_template::upgrade_proposal {
    use std::option;

    use governance::genesis::{Self, GovernanceContracts};
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::package::{UpgradeTicket, UpgradeReceipt};
    use sui::tx_context::TxContext;

    const PACKAGE_NAME: vector<u8> = b"Serde";
    const PACKAGE_ID: address = @0x6a7c03a2911856faf91387c55ffba34a1fc1b4707980c06a40a3f53c86bf3d64;
    const DIGEST: vector<u8> = x"86733bdce774f439ff87b006955a11c6500c793276bffc20d5520f4e4670f72d";
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
        governance_contracts: &mut GovernanceContracts,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ): UpgradeTicket {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_some(&governance_cap), ENOT_FINAL_VOTE);
        let cap = option::extract(&mut governance_cap);
        let ticket = genesis::authorize_upgrade(&cap, governance_contracts, PACKAGE_ID, POLICY, DIGEST);
        governance_v1::destroy_governance_cap(cap);
        option::destroy_none(governance_cap);
        ticket
    }

    public fun commit_upgrade(
        governance_contracts: &mut GovernanceContracts,
        receipt: UpgradeReceipt,
    ) {
        genesis::commit_upgrade(governance_contracts, PACKAGE_ID, receipt)
    }
}
