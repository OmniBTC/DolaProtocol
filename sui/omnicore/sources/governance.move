/// Manage permissions for modules in the protocol
module omnicore::governance {
    use std::option::{Self, Option};
    use std::vector;

    use sui::object::{Self, UID, id_address};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// Errors
    const ENOT_MEMBER: u64 = 0;

    const EALREADY_VOTE: u64 = 1;

    const EALREADY_MEMBER: u64 = 2;

    const EWRONG_VOTE_TYPE: u64 = 3;

    /// Const types
    const APPROVE_VOTE_TYPE: u8 = 0;

    const TRANSFER_VOTE_TYPE: u8 = 1;

    /// Manage governance members
    struct GovernanceCap has key, store {
        id: UID
    }

    /// Current governance members
    struct Governance has key {
        id: UID,
        members: vector<address>,
    }

    /// Vote by governance members to send a key for a proposal
    struct Vote<phantom T> has key {
        id: UID,
        // members address
        votes: vector<address>,
        // recipient of key
        beneficiary: address,
        // just record cap position
        proposal: address,
        // vote type, 0 for approve, 1 for tranfer
        vote_type: u8,
        // prevent duplicate key issuance
        finished: bool
    }

    /// Share a cap so that only the person who owns the key can use it,
    /// or the key can be wrapped in package for use.
    struct Proposal<T: key + store> has key, store {
        id: UID,
        cap: Option<T>
    }

    /// Use it to get a cap
    struct Key<phantom T> has key, store {
        id: UID
    }

    fun init(ctx: &mut TxContext) {
        let members = vector::empty<address>();
        vector::push_back(&mut members, tx_context::sender(ctx));
        transfer::transfer(GovernanceCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
        transfer::share_object(Governance {
            id: object::new(ctx),
            members
        })
    }

    public entry fun add_member(_: &GovernanceCap, goverance: &mut Governance, member: address) {
        assert!(!vector::contains(&mut goverance.members, &member), EALREADY_MEMBER);
        vector::push_back(&mut goverance.members, member)
    }

    public entry fun remove_member(_: &GovernanceCap, governance: &mut Governance, member: address) {
        is_member(governance, member);
        let (_, index) = vector::index_of(&mut governance.members, &member);
        vector::remove(&mut governance.members, index);
    }

    public fun is_member(goverance: &mut Governance, member: address) {
        assert!(vector::contains(&mut goverance.members, &member), ENOT_MEMBER)
    }

    public fun ensure_two_thirds(members_num: u64, votes_num: u64): bool {
        votes_num >= members_num * 2 / 3 + 1
    }

    /// Anyone can create proposal with a cap
    public entry fun create_proposal<T: key + store>(cap: T, ctx: &mut TxContext) {
        transfer::share_object(Proposal<T> {
            id: object::new(ctx),
            cap: option::some(cap)
        })
    }

    /// Member of governance can create vote
    public entry fun create_vote<T: key + store>(
        gov: &mut Governance,
        vote_type: u8,
        proposal: &mut Proposal<T>,
        beneficiary: address,
        ctx: &mut TxContext
    ) {
        let sponsor = tx_context::sender(ctx);
        is_member(gov, sponsor);

        let votes = vector::empty<address>();
        vector::push_back(&mut votes, sponsor);
        transfer::share_object(Vote<T> {
            id: object::new(ctx),
            votes,
            beneficiary,
            proposal: id_address(proposal),
            vote_type,
            finished: false
        });
    }

    public entry fun vote_for_transfer<T: key + store>(
        gov: &mut Governance,
        proposal: &mut Proposal<T>,
        vote: &mut Vote<T>,
        ctx: &mut TxContext
    ) {
        assert!(vote.vote_type == TRANSFER_VOTE_TYPE, EWRONG_VOTE_TYPE);
        let voter = tx_context::sender(ctx);
        is_member(gov, voter);
        let votes = &mut vote.votes;
        assert!(!vector::contains(votes, &voter), EALREADY_VOTE);
        vector::push_back(votes, voter);
        let members_num = vector::length(&gov.members);
        let votes_num = vector::length(votes);
        if (ensure_two_thirds(members_num, votes_num) && !vote.finished) {
            vote.finished = true;
            let cap = option::extract(&mut proposal.cap);
            transfer::transfer(cap, vote.beneficiary);
        }
    }

    public entry fun vote_for_approve<T: key + store>(gov: &mut Governance, vote: &mut Vote<T>, ctx: &mut TxContext) {
        assert!(vote.vote_type == APPROVE_VOTE_TYPE, EWRONG_VOTE_TYPE);
        let voter = tx_context::sender(ctx);
        is_member(gov, voter);
        let votes = &mut vote.votes;
        assert!(!vector::contains(votes, &voter), EALREADY_VOTE);
        vector::push_back(votes, voter);
        let members_num = vector::length(&gov.members);
        let votes_num = vector::length(votes);
        if (ensure_two_thirds(members_num, votes_num) && !vote.finished) {
            vote.finished = true;
            transfer::transfer(Key<T> {
                id: object::new(ctx),
            }, vote.beneficiary)
        }
    }

    public fun borrow_cap<T: key + store>(proposal: &mut Proposal<T>, _: &mut Key<T>): &T {
        option::borrow(&proposal.cap)
    }

    public entry fun destroy_key<T>(key: Key<T>) {
        let Key { id } = key;
        object::delete(id)
    }
}
