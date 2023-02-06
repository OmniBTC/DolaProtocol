/// Voting governance version 1. Using multi-person voting governance,
/// the number of people over a certain threshold proposal passed
module governance::governance_v1 {
    use std::option::{Self, Option};
    use std::vector;

    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use governance::basic::{GovernanceCap, GovernanceManagerCap, GovernanceBasic};
    use governance::basic;

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

    /// Const types
    const APPROVE_VOTE_TYPE: u8 = 7;

    const TRANSFER_VOTE_TYPE: u8 = 8;

    const EALREADY_EXIST: u64 = 9;

    const EMUST_NONE: u64 = 10;

    const EMUST_SOME: u64 = 11;

    const EVOTE_HAS_COMPLETE: u64 = 12;

    const EVOTE_NOT_START: u64 = 12;

    const EVOTE_NOT_END: u64 = 13;

    const EVOTE_HAS_EXPIRED: u64 = 13;

    const EHAS_MANAGER: u64 = 15;

    const ENOT_MANAGER: u64 = 15;


    struct GovernanceInfo has key {
        id: UID,
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
        his_proposal: vector<ID>,
        // Gonvernance manager cap
        gonvernance_manager_cap: Option<GovernanceManagerCap>
    }

    struct Proposal has key {
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
            announce_delay: 0,
            voting_delay: 0,
            max_delay: 30,
            members,
            his_proposal: vector::empty(),
            gonvernance_manager_cap: option::none()
        });
    }

    public entry fun initial_manager_cap(
        governance_basic: &mut GovernanceBasic,
        goverance_info: &mut GovernanceInfo,
        ctx: &mut TxContext
    ) {
        assert!(option::is_none(&goverance_info.gonvernance_manager_cap), EHAS_MANAGER);
        option::fill(&mut goverance_info.gonvernance_manager_cap, basic::new(governance_basic, ctx));
    }

    public fun is_member(goverance_info: &GovernanceInfo, member: address) {
        assert!(vector::contains(&goverance_info.members, &member), ENOT_MEMBER)
    }

    // Adding members through governance
    public entry fun add_member(_: &GovernanceCap, goverance_info: &mut GovernanceInfo, member: address) {
        assert!(!vector::contains(&mut goverance_info.members, &member), EALREADY_MEMBER);
        vector::push_back(&mut goverance_info.members, member)
    }

    // Removing members through governance
    public entry fun remove_member(_: &GovernanceCap, governance: &mut GovernanceInfo, member: address) {
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

    public entry fun create_proposal(
        goverance_info: &GovernanceInfo,
        package_id: address,
        ctx: &mut TxContext) {
        let creator = tx_context::sender(ctx);

        is_member(goverance_info, creator);

        let start_vote = tx_context::epoch(ctx) + goverance_info.announce_delay;
        let end_vote;
        if (goverance_info.voting_delay == 0) {
            end_vote = option::none()
        }else {
            end_vote = option::some(start_vote + goverance_info.voting_delay);
        };
        let expired = tx_context::epoch(ctx) + goverance_info.max_delay;
        transfer::share_object(Proposal {
            id: object::new(ctx),
            creator,
            start_vote,
            end_vote,
            expired,
            package_id,
            favor_votes: vector::empty(),
            against_votes: vector::empty(),
            state: PROPOSAL_ANNOUNCEMENT_PENDING
        });
    }

    fun borrow_manger_cap(goverance_info: &mut GovernanceInfo): &GovernanceManagerCap {
        assert!(option::is_some(&goverance_info.gonvernance_manager_cap), ENOT_MEMBER);
        option::borrow(&goverance_info.gonvernance_manager_cap)
    }

    public fun vote_external_cap(
        goverance_info: &mut GovernanceInfo,
        proposal: &mut Proposal,
        support: bool,
        ctx: &mut TxContext
    ): Option<GovernanceCap> {
        assert!(proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING
            || proposal.state == PROPOSAL_VOTING_PENDING, EVOTE_HAS_COMPLETE);

        let current_epoch = tx_context::epoch(ctx);
        assert!(current_epoch >= proposal.start_vote, EVOTE_NOT_START);
        assert!(current_epoch <= proposal.expired, EVOTE_HAS_EXPIRED);

        let favor_votes = &mut proposal.favor_votes;
        let against_votes = &mut proposal.against_votes;

        if (option::is_none(&proposal.end_vote) || (option::is_some(
            &proposal.end_vote
        ) && current_epoch < *option::borrow(&proposal.end_vote))) {
            let voter = tx_context::sender(ctx);
            is_member(goverance_info, voter);


            assert!(!vector::contains(favor_votes, &voter)
                && !vector::contains(against_votes, &voter), EALREADY_VOTE);

            if (support) {
                vector::push_back(favor_votes, voter);
            }else {
                vector::push_back(against_votes, voter);
            };
        };

        if (option::is_none(&proposal.end_vote) || (option::is_some(
            &proposal.end_vote
        ) && current_epoch >= *option::borrow(&proposal.end_vote))) {
            let members_num = vector::length(&goverance_info.members);
            let favor_votes_num = vector::length(favor_votes);
            if (ensure_two_thirds(members_num, favor_votes_num)) {
                proposal.state = PROPOSAL_SUCCESS;
                option::some(basic::create(borrow_manger_cap(goverance_info)))
            }else {
                if (option::is_some(&proposal.end_vote)) {
                    proposal.state = PROPOSAL_FAIL;
                };
                option::none()
            }
        }else {
            option::none()
        }
    }

    public fun borrow_governance_cap(governance_cap: &mut Option<GovernanceCap>): &mut GovernanceCap {
        assert!(option::is_some(governance_cap), EMUST_SOME);
        option::borrow_mut(governance_cap)
    }

    public fun destroy_governance_cap(
        goverance_info: &mut GovernanceInfo,
        governance_cap: Option<GovernanceCap>
    ) {
        if (option::is_some(&governance_cap)) {
            basic::destroy(borrow_manger_cap(goverance_info), option::destroy_some(governance_cap));
        }else {
            option::destroy_none(governance_cap);
        }
    }
}
