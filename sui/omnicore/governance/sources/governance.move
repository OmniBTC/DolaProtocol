/// Manage permissions for modules in the protocol
module governance::governance {
    use std::hash;
    use std::option::{Self, Option};
    use std::vector;

    use sui::bcs;
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID, id_address, uid_to_address};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    #[test_only]
    use sui::test_scenario;

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


    struct GovernanceExternalCap has key, store {
        id: UID
    }

    /// Manage governance module
    /// todo: need a more democratic way to use it.
    struct GovernanceManagerCap has key, store {
        id: UID
    }

    /// Govern the calls of other contracts, and other contracts
    /// using governance only need to take this cap parameter.
    struct GovernanceCap has store, drop {
        governance_manager: address
    }

    /// Current governance members
    struct Governance has key {
        id: UID,
        members: vector<address>,
    }

    /// Vote by governance members to send a key for a proposal
    /// or retrun cap from governance.
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
        // manual or contract calls to get a key or cap
        claim: bool,
        // prevent duplicate key issuance
        finished: bool
    }

    /// Vote by governance members to send a key for a proposal
    struct VoteExternalCap has key {
        id: UID,
        // members address
        votes: vector<address>,
        // External cap hash
        external_hash: vector<u8>,
        // prevent duplicate key issuance
        finished: bool
    }

    struct FlashCap<T> {
        // External cap
        external_cap: T,
    }

    /// Share a cap so that only the person who owns the key can use it,
    /// or the key can be wrapped in package for use.
    struct Proposal<T: key + store> has key {
        id: UID,
        cap: Option<T>
    }

    /// Use it to get a cap
    struct Key<phantom T> has key, store {
        id: UID
    }

    /// Help to get the key of dynamic object
    struct AddExternalCapEvent has store, copy, drop {
        hash: vector<u8>
    }

    fun init(ctx: &mut TxContext) {
        let members = vector::empty<address>();
        vector::push_back(&mut members, tx_context::sender(ctx));
        transfer::transfer(GovernanceManagerCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
        transfer::share_object(Governance {
            id: object::new(ctx),
            members
        });
        transfer::share_object(GovernanceExternalCap {
            id: object::new(ctx)
        })
    }

    public entry fun add_external_cap<T: store>(
        governance_external_cap: &mut GovernanceExternalCap,
        hash: vector<u8>,
        cap: T
    ) {
        assert!(!dynamic_field::exists_with_type<vector<u8>, T>(&governance_external_cap.id, hash), EALREADY_EXIST);
        dynamic_field::add(&mut governance_external_cap.id, hash, cap);
        emit(AddExternalCapEvent {
            hash
        })
    }

    public entry fun register_governance_cap(
        governance_manager: &GovernanceManagerCap,
        governance_external_cap: &mut GovernanceExternalCap,
    ) {
        let cap = GovernanceCap { governance_manager: uid_to_address(&governance_manager.id) };
        add_external_cap(governance_external_cap, hash::sha3_256(bcs::to_bytes(&cap)), cap);
    }

    public entry fun add_member(_: &GovernanceManagerCap, goverance: &mut Governance, member: address) {
        assert!(!vector::contains(&mut goverance.members, &member), EALREADY_MEMBER);
        vector::push_back(&mut goverance.members, member)
    }

    public entry fun remove_member(_: &GovernanceManagerCap, governance: &mut Governance, member: address) {
        is_member(governance, member);
        let (_, index) = vector::index_of(&mut governance.members, &member);
        vector::remove(&mut governance.members, index);
    }

    public fun is_member(goverance: &mut Governance, member: address) {
        assert!(vector::contains(&mut goverance.members, &member), ENOT_MEMBER)
    }

    // todo: maybe through number of proxy votes when there is a governance token
    public fun ensure_two_thirds(members_num: u64, votes_num: u64): bool {
        let threshold =
            if (members_num % 3 == 0) {
                members_num * 2 / 3
            } else {
                members_num * 2 / 3 + 1
            };
        votes_num >= threshold
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
        claim: bool,
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
            claim,
            finished: false
        });
    }

    public fun claim_key<T: key + store>(gov: &mut Governance, vote: &mut Vote<T>, ctx: &mut TxContext): Key<T> {
        assert!(vote.claim, ECANNOT_CLAIM);
        let beneficiary = tx_context::sender(ctx);
        assert!(beneficiary == vote.beneficiary, ENOT_BENEFICIARY);
        let members_num = vector::length(&gov.members);
        let votes_num = vector::length(&mut vote.votes);
        assert!((ensure_two_thirds(members_num, votes_num)), EVOTE_NOT_COMPLETE);
        assert!(!vote.finished, EVOTE_NOT_COMPLETE);
        vote.finished = true;
        Key<T> {
            id: object::new(ctx),
        }
    }

    public fun claim_cap<T: key + store>(
        gov: &mut Governance,
        vote: &mut Vote<T>,
        proposal: &mut Proposal<T>,
        ctx: &mut TxContext
    ): T {
        assert!(vote.claim, ECANNOT_CLAIM);
        let beneficiary = tx_context::sender(ctx);
        assert!(beneficiary == vote.beneficiary, ENOT_BENEFICIARY);
        let members_num = vector::length(&gov.members);
        let votes_num = vector::length(&mut vote.votes);
        assert!((ensure_two_thirds(members_num, votes_num)), EVOTE_NOT_COMPLETE);
        assert!(!vote.finished, EVOTE_NOT_COMPLETE);
        vote.finished = true;
        let cap = option::extract(&mut proposal.cap);
        cap
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

        let members_num = vector::length(&gov.members);
        if (members_num != 1) {
            assert!(!vector::contains(votes, &voter), EALREADY_VOTE);
            vector::push_back(votes, voter);
        };

        let votes_num = vector::length(votes);
        if (ensure_two_thirds(members_num, votes_num) && !vote.finished && !vote.claim) {
            vote.finished = true;
            let cap = option::extract(&mut proposal.cap);
            transfer::transfer(cap, vote.beneficiary);
        }
    }

    public entry fun create_vote_external_cap(
        gov: &mut Governance,
        external_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sponsor = tx_context::sender(ctx);
        is_member(gov, sponsor);

        let votes = vector::empty<address>();
        vector::push_back(&mut votes, sponsor);
        // Like MakeDao
        transfer::share_object(VoteExternalCap {
            id: object::new(ctx),
            votes,
            external_hash,
            finished: false
        });
    }

    public entry fun vote_for_approve<T: key + store>(gov: &mut Governance, vote: &mut Vote<T>, ctx: &mut TxContext) {
        assert!(vote.vote_type == APPROVE_VOTE_TYPE, EWRONG_VOTE_TYPE);
        let voter = tx_context::sender(ctx);
        is_member(gov, voter);
        let votes = &mut vote.votes;
        let members_num = vector::length(&gov.members);
        if (members_num != 1) {
            assert!(!vector::contains(votes, &voter), EALREADY_VOTE);
            vector::push_back(votes, voter);
        };
        let votes_num = vector::length(votes);
        if (ensure_two_thirds(members_num, votes_num) && !vote.finished && !vote.claim) {
            vote.finished = true;
            transfer::transfer(Key<T> {
                id: object::new(ctx),
            }, vote.beneficiary)
        }
    }

    public fun vote_external_cap<T: store>(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        ctx: &mut TxContext
    ): Option<FlashCap<T>> {
        assert!(!vote.finished, EVOTE_HAS_COMPLETE);
        let voter = tx_context::sender(ctx);
        is_member(gov, voter);
        let votes = &mut vote.votes;
        let members_num = vector::length(&gov.members);
        if (members_num != 1) {
            assert!(!vector::contains(votes, &voter), EALREADY_VOTE);
            vector::push_back(votes, voter);
        };
        let votes_num = vector::length(votes);
        if (ensure_two_thirds(members_num, votes_num) && !vote.finished) {
            vote.finished = true;
            option::some(FlashCap {
                external_cap: dynamic_field::remove<vector<u8>, T>(
                    &mut governance_external_cap.id,
                    vote.external_hash)
            })
        }else {
            option::none()
        }
    }

    public fun borrow_external_cap<T: store+drop>(flash_cap: &mut Option<FlashCap<T>>): &mut T {
        assert!(option::is_some(flash_cap), EMUST_SOME);
        &mut option::borrow_mut(flash_cap).external_cap
    }

    public fun migrate_external_cap<T: store+drop>(flash_cap: Option<FlashCap<T>>): T {
        // todo! consider whether to limit function call
        assert!(option::is_some(&flash_cap), EMUST_SOME);
        let FlashCap { external_cap } = option::destroy_some(flash_cap);
        external_cap
    }

    public fun external_cap_destroy<T: store>(
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        flash_cap: Option<FlashCap<T>>
    ) {
        if (option::is_some(&flash_cap)) {
            assert!(vote.finished, EVOTE_NOT_COMPLETE);
            let flash_cap = option::destroy_some(flash_cap);
            let FlashCap { external_cap } = flash_cap;
            dynamic_field::add(&mut governance_external_cap.id, vote.external_hash, external_cap);
        }else {
            option::destroy_none(flash_cap);
        }
    }

    public fun borrow_from_proposal<T: key + store>(proposal: &mut Proposal<T>, _: &mut Key<T>): &T {
        option::borrow(&proposal.cap)
    }

    /// If someone or an app no longer borrows cap, destroy its key
    public entry fun destroy_key<T>(key: Key<T>) {
        let Key { id } = key;
        object::delete(id)
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    struct TestCap has key, store {
        id: UID
    }

    #[test_only]
    public fun test_cap(_: &TestCap): bool {
        true
    }

    #[test]
    public fun test_govern_cap() {
        let first_member = @0xA;
        let second_member = @0xB;
        let third_member = @0xC;
        let pool_manager = @0xD;
        let app = @0xE;

        let scenario_val = test_scenario::begin(first_member);
        let scenario = &mut scenario_val;
        {
            init_for_test(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, first_member);
        {
            let test_cap = TestCap { id: object::new(test_scenario::ctx(scenario)) };
            transfer::transfer(test_cap, pool_manager);
        };
        test_scenario::next_tx(scenario, pool_manager);
        {
            let test_cap = test_scenario::take_from_sender<TestCap>(scenario);
            create_proposal(test_cap, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, first_member);
        {
            let shared_proposal = test_scenario::take_shared<Proposal<TestCap>>(scenario);
            let shared_governance = test_scenario::take_shared<Governance>(scenario);
            create_vote<TestCap>(
                &mut shared_governance,
                APPROVE_VOTE_TYPE,
                &mut shared_proposal,
                app,
                false,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(shared_proposal);
            test_scenario::return_shared(shared_governance);
        };
        test_scenario::next_tx(scenario, first_member);
        {
            let shared_governance = test_scenario::take_shared<Governance>(scenario);
            let shared_vote = test_scenario::take_shared<Vote<TestCap>>(scenario);
            vote_for_approve(&mut shared_governance, &mut shared_vote, test_scenario::ctx(scenario));

            test_scenario::return_shared(shared_governance);
            test_scenario::return_shared(shared_vote);
        };
        test_scenario::next_tx(scenario, app);
        {
            let proposal = test_scenario::take_shared<Proposal<TestCap>>(scenario);
            let key = test_scenario::take_from_sender<Key<TestCap>>(scenario);
            let cap = borrow_from_proposal(&mut proposal, &mut key);
            assert!(test_cap(cap), 0);

            test_scenario::return_shared(proposal);
            test_scenario::return_to_sender(scenario, key);
        };
        test_scenario::next_tx(scenario, first_member);
        {
            let goverance_cap = test_scenario::take_from_sender<GovernanceManagerCap>(scenario);
            let goverance = test_scenario::take_shared<Governance>(scenario);
            add_member(&goverance_cap, &mut goverance, second_member);

            test_scenario::return_shared(goverance);
            test_scenario::return_to_sender(scenario, goverance_cap);
        };
        test_scenario::next_tx(scenario, first_member);
        {
            let goverance_cap = test_scenario::take_from_sender<GovernanceManagerCap>(scenario);
            let goverance = test_scenario::take_shared<Governance>(scenario);
            add_member(&goverance_cap, &mut goverance, third_member);

            test_scenario::return_shared(goverance);
            test_scenario::return_to_sender(scenario, goverance_cap);
        };
        test_scenario::next_tx(scenario, second_member);
        {
            let shared_proposal = test_scenario::take_shared<Proposal<TestCap>>(scenario);
            let shared_governance = test_scenario::take_shared<Governance>(scenario);
            create_vote<TestCap>(
                &mut shared_governance,
                TRANSFER_VOTE_TYPE,
                &mut shared_proposal,
                app,
                false,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(shared_proposal);
            test_scenario::return_shared(shared_governance);
        };
        test_scenario::next_tx(scenario, third_member);
        {
            let shared_governance = test_scenario::take_shared<Governance>(scenario);
            let shared_proposal = test_scenario::take_shared<Proposal<TestCap>>(scenario);
            let recent_vote_id = test_scenario::most_recent_id_shared<Vote<TestCap>>();
            let shared_vote = test_scenario::take_shared_by_id<Vote<TestCap>>(
                scenario,
                option::extract(&mut recent_vote_id)
            );
            vote_for_transfer(
                &mut shared_governance,
                &mut shared_proposal,
                &mut shared_vote,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shared_governance);
            test_scenario::return_shared(shared_proposal);
            test_scenario::return_shared(shared_vote);
        };
        test_scenario::next_tx(scenario, app);
        {
            let cap = test_scenario::take_from_sender<TestCap>(scenario);
            assert!(test_cap(&cap), 0);
            test_scenario::return_to_sender(scenario, cap);
        };
        test_scenario::end(scenario_val);
    }
}
