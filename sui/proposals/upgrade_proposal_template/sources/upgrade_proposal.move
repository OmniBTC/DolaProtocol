module upgrade_proposal_template::upgrade_proposal {
    use std::option;

    use governance::genesis::{Self, GovernanceContracts};
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::package::{UpgradeTicket, UpgradeReceipt};
    use sui::tx_context::TxContext;

    const PACKAGE_ID: address = @0x4d24960e8247212dbb7b28156ba6753b1b5f180a3b321a9dc3d69a1e8fcf5ba7;
    const DIGEST: vector<u8> = x"a58e1d08924bd5fe9379e04c3958005aa03a71feea935be08516c461714e97dd";
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
