module 0x1::treasury {
    use std::option::{Self, Option};

    use governance::genesis::GovernanceCap;
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use lending_core::storage::Storage;
    use pool_manager::pool_manager::PoolManagerInfo;
    use sui::clock::Clock;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const E_FINISHED_PROPOSAL: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    struct ProposalInfo has key {
        id: UID,
        proposal_num: u64,
        proposal_cap: Option<GovernanceCap>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(ProposalInfo {
            id: object::new(ctx),
            proposal_num: 1,
            proposal_cap: option::none()
        })
    }

    fun get_proposal_cap(proposal_info: &mut ProposalInfo): &GovernanceCap {
        proposal_info.proposal_num = proposal_info.proposal_num - 1;
        assert!(proposal_info.proposal_num > 0, E_FINISHED_PROPOSAL);
        option::borrow(&proposal_info.proposal_cap)
    }

    fun destory_cap(proposal_info: &mut ProposalInfo) {
        if (proposal_info.proposal_num == 0) {
            let proposal_cap = option::extract(&mut proposal_info.proposal_cap);
            governance_v1::destory_governance_cap(proposal_cap);
        }
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

    public entry fun claim_from_treasury(
        pool_manager_info: &mut PoolManagerInfo,
        proposal_info: &mut ProposalInfo,
        storage: &mut Storage,
        clock: &Clock,
        dola_pool_id: u16,
        dola_user_id: u64,
        amount: u64,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);
        let storage_cap = lending_core::storage::register_cap_with_governance(governance_cap);
        lending_core::logic::claim_from_treasury(
            governance_cap,
            &storage_cap,
            pool_manager_info,
            storage,
            clock,
            dola_pool_id,
            dola_user_id,
            (amount as u256)
        );

        destory_cap(proposal_info);
    }
}
