module test_proposal::test {
    use std::option::{Self, Option};

    use app_manager::app_manager::{Self, TotalAppInfo};
    use dola_types::dola_contract::DolaContractRegistry;
    use governance::genesis::{Self, GovernanceCap, GovernanceContracts};
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::object::{Self, UID};
    use sui::package::{UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer;
    use sui::tx_context::TxContext;

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

    public entry fun vote_proposal(
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

    public entry fun join_app_manager(
        governance_contract: &mut GovernanceContracts,
        total_app_info: &mut TotalAppInfo,
        dola_registry: &mut DolaContractRegistry,
        proposal_info: &mut ProposalInfo,
        upgrade_cap: UpgradeCap
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        app_manager::register_dola_contract(
            governance_cap,
            governance_contract,
            total_app_info,
            dola_registry,
            upgrade_cap
        )
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
