module upgrade_proposal::upgrade_proposal {
    use std::option::{Self, Option};

    use governance::genesis::{Self, GovernanceCap, GovernanceContracts};
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::object::{Self, UID};
    use sui::package::{UpgradeTicket, UpgradeReceipt};
    use sui::transfer;
    use sui::tx_context::TxContext;

    // todo: use const to define upgrade info
    // const DOLA_CONTRACT_ID: u256 = 1;
    // const DIGEST: bytes32 = x"";
    // const POLICY: u8 = 0;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    struct ProposalInfo has key {
        id: UID,
        proposal_cap: Option<GovernanceCap>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(ProposalInfo {
            id: object::new(ctx),
            proposal_cap: option::none()
        })
    }

    fun get_proposal_cap(proposal_info: &mut ProposalInfo): &GovernanceCap {
        option::borrow(&proposal_info.proposal_cap)
    }

    fun destroy_cap(proposal_info: &mut ProposalInfo) {
        let proposal_cap = option::extract(&mut proposal_info.proposal_cap);
        governance_v1::destroy_governance_cap(proposal_cap);
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

    public fun upgrade_package(
        proposal_info: &mut ProposalInfo,
        gov_contracts: &mut GovernanceContracts,
        dola_contract_id: u256,
        policy: u8,
        digest: vector<u8>
    ): UpgradeTicket {
        let gov_cap = get_proposal_cap(proposal_info);
        genesis::authorize_upgrade(gov_cap, gov_contracts, dola_contract_id, policy, digest)
    }

    public fun commit_upgrade(
        proposal_info: &mut ProposalInfo,
        gov_contracts: &mut GovernanceContracts,
        dola_contract_id: u256,
        receipt: UpgradeReceipt
    ) {
        genesis::commit_upgrade(gov_contracts, dola_contract_id, receipt);
        destroy_cap(proposal_info);
    }
}
