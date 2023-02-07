/// Voting governance version 1. Using multi-person voting governance,
/// the number of people over a certain threshold proposal passed.
module governance::governance_v1 {
    use std::option::{Self, Option};
    use std::vector;

    use governance::genesis::{Self, GovernanceCap, GovernanceManagerCap, GovernanceGenesis};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// Proposal State
    // Proposal announcement waiting period
    const PROPOSAL_ANNOUNCEMENT_PENDING: u8 = 1;

    // Proposal voting waiting period
    const PROPOSAL_VOTING_PENDING: u8 = 2;

    // Proposal success
    const PROPOSAL_SUCCESS: u8 = 3;

    // Proposal fail
    const PROPOSAL_FAIL: u8 = 4;

    // Proposal cancel
    const PROPOSAL_CANCEL: u8 = 5;

    /// Errors
    const ENOT_MEMBER: u64 = 0;

    const EALREADY_VOTE: u64 = 1;

    const EALREADY_MEMBER: u64 = 2;

    const EWRONG_VOTE_TYPE: u64 = 3;

    const ENOT_BENEFICIARY: u64 = 4;

    const ECANNOT_CLAIM: u64 = 5;

    const EVOTE_NOT_COMPLETE: u64 = 6;

    const EALREADY_EXIST: u64 = 7;

    const EMUST_NONE: u64 = 8;

    const EMUST_SOME: u64 = 9;

    const EVOTE_HAS_COMPLETE: u64 = 10;

    const EVOTE_NOT_START: u64 = 11;

    const EVOTE_NOT_END: u64 = 12;

    const EVOTE_HAS_EXPIRED: u64 = 13;

    const EHAS_ACTIVATED: u64 = 14;

    const ENOT_ACTIVE: u64 = 15;


    struct GovernanceInfo has key {
        id: UID,
        // Gonvernance manager cap
        gonvernance: Option<GovernanceManagerCap>,
        // Governance active state
        active: bool,
        // Proposal announcement period waiting time
        announce_delay: u64,
        // Vote waiting time
        voting_delay: u64,
        // The maximum duration of proposal.
        // max_delay > voting_delay + announce_delay
        max_delay: u64,
        // Vote members
        members: vector<address>,
        // History proposal
        his_proposal: vector<ID>
    }

    struct Proposal<T> has key {
        id: UID,
        // creator of the proposal
        creator: address,
        // Start time of vote
        start_vote: u64,
        // End time of vote
        end_vote: Option<u64>,
        // Expired time of proposal
        expired: u64,
        // Package id of the proposal
        package_id: address,
        // Certificate of proposal
        certificate: Option<T>,
        // Members who voted in favor
        favor_votes: vector<address>,
        // Members who voted against
        against_votes: vector<address>,
        // prevent duplicate key issuance
        state: u8
    }

    fun init(ctx: &mut TxContext) {
        let members = vector::empty<address>();
        vector::push_back(&mut members, tx_context::sender(ctx));
        transfer::share_object(GovernanceInfo {
            id: object::new(ctx),
            gonvernance: option::none(),
            active: false,
            announce_delay: 0,
            voting_delay: 0,
            max_delay: 30,
            members,
            his_proposal: vector::empty(),
        });
    }

    /// Activate the current version of governance.
    public entry fun activate_governance(
        governance_genesis: &mut GovernanceGenesis,
        governance_info: &mut GovernanceInfo,
        ctx: &mut TxContext
    ) {
        assert!(!governance_info.active, EHAS_ACTIVATED);
        option::fill(&mut governance_info.gonvernance, genesis::new(governance_genesis, ctx));
        governance_info.active = true;
    }

    /// After the upgrade, all current governance members will be invalidated.
    public fun upgrade_to_v2(_: &GovernanceCap, governance_info: &mut GovernanceInfo): GovernanceManagerCap {
        let governance_manager_cap = option::extract(&mut governance_info.gonvernance);
        governance_info.active = false;
        governance_manager_cap
    }

    public fun is_member(governance_info: &GovernanceInfo, member: address) {
        assert!(vector::contains(&governance_info.members, &member), ENOT_MEMBER)
    }

    /// Add members through governance.
    public fun add_member(_: &GovernanceCap, governance_info: &mut GovernanceInfo, member: address) {
        assert!(!vector::contains(&mut governance_info.members, &member), EALREADY_MEMBER);
        vector::push_back(&mut governance_info.members, member)
    }

    /// Remove members through governance.
    public fun remove_member(_: &GovernanceCap, governance: &mut GovernanceInfo, member: address) {
        is_member(governance, member);
        let (_, index) = vector::index_of(&mut governance.members, &member);
        vector::remove(&mut governance.members, index);
    }

    public fun ensure_two_thirds(members_num: u64, votes_num: u64): bool {
        let threshold =
            if (members_num % 3 == 0) {
                members_num * 2 / 3
            } else {
                members_num * 2 / 3 + 1
            };
        votes_num >= threshold
    }

    /// When creating the proposal, you need to give the certificate in the contract
    /// to ensure that the proposal can only be executed in that contract.
    public fun create_proposal<T: store>(
        governance_info: &GovernanceInfo,
        package_id: address,
        certificate: Option<T>,
        ctx: &mut TxContext
    ) {
        assert!(governance_info.active, ENOT_ACTIVE);
        let creator = tx_context::sender(ctx);

        is_member(governance_info, creator);

        let start_vote = tx_context::epoch(ctx) + governance_info.announce_delay;
        let end_vote;
        if (governance_info.voting_delay == 0) {
            end_vote = option::none()
        }else {
            end_vote = option::some(start_vote + governance_info.voting_delay);
        };
        let expired = tx_context::epoch(ctx) + governance_info.max_delay;
        transfer::share_object(Proposal<T> {
            id: object::new(ctx),
            creator,
            start_vote,
            end_vote,
            expired,
            package_id,
            certificate,
            favor_votes: vector::empty(),
            against_votes: vector::empty(),
            state: PROPOSAL_ANNOUNCEMENT_PENDING
        });
    }


    /// Vote for a proposal
    public entry fun vote_for_proposal<T: store>(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<T>,
        support: bool,
        ctx: &mut TxContext
    ) {
        assert!(proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING
            || proposal.state == PROPOSAL_VOTING_PENDING, EVOTE_HAS_COMPLETE);

        let current_epoch = tx_context::epoch(ctx);
        assert!(current_epoch >= proposal.start_vote, EVOTE_NOT_START);
        assert!(current_epoch <= proposal.expired, EVOTE_HAS_EXPIRED);

        let favor_votes = &mut proposal.favor_votes;
        let against_votes = &mut proposal.against_votes;

        if (option::is_none(&proposal.end_vote) || current_epoch < *option::borrow(&proposal.end_vote)) {
            let voter = tx_context::sender(ctx);
            is_member(governance_info, voter);

            assert!(!vector::contains(favor_votes, &voter)
                && !vector::contains(against_votes, &voter), EALREADY_VOTE);

            if (support) {
                vector::push_back(favor_votes, voter);
            }else {
                vector::push_back(against_votes, voter);
            };
        }
    }

    public fun execute_proposal<T>(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<T>,
        ctx: &mut TxContext
    ): (Option<GovernanceCap>, Option<T>) {
        let current_epoch = tx_context::epoch(ctx);
        let end_epoch = if (option::is_none(&proposal.end_vote)) { 0 } else { *option::borrow(&proposal.end_vote) };
        assert!(current_epoch >= end_epoch, EVOTE_NOT_END);
        assert!(proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING
            || proposal.state == PROPOSAL_VOTING_PENDING, EVOTE_HAS_COMPLETE);

        is_member(governance_info, tx_context::sender(ctx));

        let members_num = vector::length(&governance_info.members);
        let favor_votes_num = vector::length(&proposal.favor_votes);
        if (ensure_two_thirds(members_num, favor_votes_num)) {
            proposal.state = PROPOSAL_SUCCESS;
            (option::some(genesis::create(option::borrow(&governance_info.gonvernance))), option::some(
                option::extract(&mut proposal.certificate)
            ))
        } else {
            if (option::is_some(&proposal.end_vote)) {
                proposal.state = PROPOSAL_FAIL;
            };
            (option::none(), option::none())
        }
    }
}
