// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Voting governance version 1. Using multi-person voting governance,
/// the number of people over a certain threshold proposal passed.
/// Note: when reviewing proposal, make sure that the `certificate` in the proposal will only flow to
/// this contract. It is created to avoid the possibility of unknown contracts gaining access
module dola_protocol::governance_v1 {
    use std::ascii::{Self, String};
    use std::option::{Self, Option};
    use std::type_name;
    use std::vector;

    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::package::UpgradeCap;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use dola_protocol::genesis::{Self, GovernanceCap, GovernanceManagerCap};

    #[test_only]
    use dola_protocol::genesis::GovernanceGenesis;
    #[test_only]
    use sui::object::id_from_address;
    #[test_only]
    use sui::package;
    #[test_only]
    use sui::test_scenario::{Self, Scenario};
    use sui::dynamic_field;

    /// Proposal State
    /// PROPOSAL_ANNOUNCEMENT_PENDING -> PROPOSAL_VOTING_PENDING -> PROPOSAL_SUCCESS/PROPOSAL_FAIL
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
    // This governance has active
    const EHAS_ACTIVE: u64 = 0;

    // This governance hasn't active
    const ENOT_ACTIVE: u64 = 1;

    // Invalid delay setting
    const EINVALID_DELAY: u64 = 2;

    // The user is not members of governance
    const EINVALID_MEMBER: u64 = 3;

    // The user is already a member of governance
    const EALREADY_MEMBER: u64 = 4;

    // The user has voted
    const EALREADY_VOTED: u64 = 5;

    // Voting has not started
    const EVOTE_NOT_STARTED: u64 = 6;

    // Voting has started
    const EVOTE_HAS_STARTED: u64 = 7;

    // Voting has completed
    const EVOTE_HAS_COMPLETED: u64 = 8;

    // Voting has expired
    const EVOTE_HAS_EXPIRED: u64 = 9;

    // The user is not a proposal creator
    const ENOT_CREATEOR: u64 = 10;


    struct GovernanceInfo has key {
        id: UID,
        // Gonvernance manager cap
        governance_manager_cap: Option<GovernanceManagerCap>,
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

    struct Proposal<T: store + drop> has key {
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
        package_id: String,
        // Certificate of proposal
        certificate: T,
        // Members who voted in favor
        favor_votes: vector<address>,
        // Members who voted against
        against_votes: vector<address>,
        // proposal state
        state: u8
    }

    struct ProposalDescId has copy, drop, store {}

    /// Events

    /// Create proposal
    struct CreateProposal has copy, drop {
        proposal_id: ID
    }

    /// Change proposal state
    struct ChangeState has copy, drop {
        proposal_id: ID,
        new_state: u8
    }

    fun init(ctx: &mut TxContext) {
        let members = vector::empty<address>();
        vector::push_back(&mut members, tx_context::sender(ctx));
        transfer::share_object(GovernanceInfo {
            id: object::new(ctx),
            governance_manager_cap: option::none(),
            active: false,
            announce_delay: 0,
            voting_delay: 0,
            max_delay: 30,
            members,
            his_proposal: vector::empty(),
        });
    }

    /// === Initial Functions ===

    /// Activate the current version of governance.
    public entry fun activate_governance(
        upgrade_cap: UpgradeCap,
        governance_info: &mut GovernanceInfo,
        ctx: &mut TxContext
    ) {
        check_member(governance_info, tx_context::sender(ctx));
        assert!(!governance_info.active && vector::length(&governance_info.his_proposal) == 0, EHAS_ACTIVE);
        option::fill(&mut governance_info.governance_manager_cap, genesis::init_genesis(upgrade_cap, ctx));
        governance_info.active = true;
    }

    /// === Governance Functions ===

    /// After the upgrade, all current governance members will be invalidated.
    public fun upgrade(_: &GovernanceCap, governance_info: &mut GovernanceInfo): GovernanceManagerCap {
        let governance_manager_cap = option::extract(&mut governance_info.governance_manager_cap);
        governance_info.active = false;
        governance_manager_cap
    }

    /// Add members through governance.
    public fun add_member(_: &GovernanceCap, governance_info: &mut GovernanceInfo, member: address) {
        assert!(!vector::contains(&mut governance_info.members, &member), EALREADY_MEMBER);
        vector::push_back(&mut governance_info.members, member)
    }

    /// Remove members through governance.
    public fun remove_member(_: &GovernanceCap, governance_info: &mut GovernanceInfo, member: address) {
        check_member(governance_info, member);
        let (_, index) = vector::index_of(&mut governance_info.members, &member);
        vector::remove(&mut governance_info.members, index);
    }

    /// Update delay through governance
    public fun update_delay(
        _: &GovernanceCap,
        governance_info: &mut GovernanceInfo,
        announce_delay: u64,
        voting_delay: u64,
        max_delay: u64
    ) {
        assert!(max_delay > voting_delay + announce_delay, EINVALID_DELAY);
        governance_info.announce_delay = announce_delay;
        governance_info.voting_delay = voting_delay;
        governance_info.max_delay = max_delay;
    }

    /// === Helper Functions ===

    /// Check if the user is a member of governance
    public fun check_member(governance_info: &GovernanceInfo, member: address) {
        assert!(vector::contains(&governance_info.members, &member), EINVALID_MEMBER)
    }

    public fun ensure_two_thirds(votes_num: u64, favor_num: u64): bool {
        let threshold =
            if (votes_num % 3 == 0) {
                votes_num * 2 / 3
            } else {
                votes_num * 2 / 3 + 1
            };
        favor_num >= threshold
    }

    /// Get proposal state
    public fun get_proposal_state<T: store + drop>(
        proposal: &mut Proposal<T>,
        ctx: &mut TxContext
    ): String {
        let current_epoch = tx_context::epoch(ctx);
        if (proposal.state == PROPOSAL_SUCCESS) {
            ascii::string(b"SUCCESS")
        }else if (proposal.state == PROPOSAL_FAIL) {
            ascii::string(b"FAIL")
        }else if (proposal.state == PROPOSAL_CANCEL) {
            ascii::string(b"CANCEL")
        }else if (current_epoch >= proposal.expired) {
            ascii::string(b"EXPIRED")
        }else if (proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING) {
            ascii::string(b"ANNOUNCEMENT_PENDING")
        }else {
            ascii::string(b"VOTING_PENDING")
        }
    }

    /// Get his proposal
    public fun get_his_proposal(
        governance_info: &GovernanceInfo
    ): &vector<ID> {
        &governance_info.his_proposal
    }

    /// Destory governance cap
    public fun destroy_governance_cap(
        governance_cap: GovernanceCap
    ) {
        genesis::destroy(governance_cap);
    }

    /// === Entry Functions ===

    /// Record historical proposal information after entering the era of multi-party governance
    public fun create_proposal_with_history<T: store + drop>(
        governance_info: &mut GovernanceInfo,
        certificate: T,
        ctx: &mut TxContext
    ) {
        assert!(governance_info.active, ENOT_ACTIVE);
        let creator = tx_context::sender(ctx);

        check_member(governance_info, creator);

        let start_vote = tx_context::epoch(ctx) + governance_info.announce_delay;
        let end_vote;
        if (governance_info.voting_delay == 0) {
            end_vote = option::none()
        } else {
            end_vote = option::some(start_vote + governance_info.voting_delay);
        };
        let expired = tx_context::epoch(ctx) + governance_info.max_delay;

        let id = object::new(ctx);
        let proposal_id = *object::uid_as_inner(&id);
        vector::push_back(&mut governance_info.his_proposal, proposal_id);

        transfer::share_object(Proposal {
            id,
            creator,
            start_vote,
            end_vote,
            expired,
            package_id: type_name::get_address(&type_name::get<T>()),
            certificate,
            favor_votes: vector::empty(),
            against_votes: vector::empty(),
            state: PROPOSAL_ANNOUNCEMENT_PENDING
        });

        event::emit(CreateProposal {
            proposal_id
        });
    }

    /// When creating the proposal, you need to give the certificate in the contract
    /// to ensure that the proposal can only be executed in that contract.
    /// certificate: When reviewing the proposal, make sure that the `certificate` in the proposal will only flow to
    /// this contract. It is created to avoid the possibility of unknown contracts gaining access
    public fun create_proposal<T: store + drop>(
        governance_info: &GovernanceInfo,
        certificate: T,
        ctx: &mut TxContext
    ) {
        assert!(governance_info.active, ENOT_ACTIVE);
        let creator = tx_context::sender(ctx);

        check_member(governance_info, creator);

        let start_vote = tx_context::epoch(ctx) + governance_info.announce_delay;
        let end_vote;
        if (governance_info.voting_delay == 0) {
            end_vote = option::none()
        }else {
            end_vote = option::some(start_vote + governance_info.voting_delay);
        };
        let expired = tx_context::epoch(ctx) + governance_info.max_delay;

        let id = object::new(ctx);
        let proposal_id = *object::uid_as_inner(&id);

        transfer::share_object(Proposal {
            id,
            creator,
            start_vote,
            end_vote,
            expired,
            package_id: type_name::get_address(&type_name::get<T>()),
            certificate,
            favor_votes: vector::empty(),
            against_votes: vector::empty(),
            state: PROPOSAL_ANNOUNCEMENT_PENDING
        });

        event::emit(CreateProposal {
            proposal_id
        });
    }

    /// Vote for a proposal
    /// `certificate`: The purpose of passing in the certificate is to ensure that the
    /// vote_proposal is only called by the proposal contract
    public fun vote_proposal<T: store + drop>(
        governance_info: &GovernanceInfo,
        _certificate: T,
        proposal: &mut Proposal<T>,
        support: bool,
        ctx: &mut TxContext
    ): Option<GovernanceCap> {
        let current_epoch = tx_context::epoch(ctx);
        assert!(current_epoch >= proposal.start_vote, EVOTE_NOT_STARTED);
        assert!(current_epoch < proposal.expired, EVOTE_HAS_EXPIRED);

        if (proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING) {
            proposal.state = PROPOSAL_VOTING_PENDING;
            event::emit(ChangeState {
                proposal_id: object::id(proposal),
                new_state: PROPOSAL_VOTING_PENDING
            });
        };

        assert!(proposal.state == PROPOSAL_VOTING_PENDING, EVOTE_HAS_COMPLETED);

        let voter = tx_context::sender(ctx);
        check_member(governance_info, voter);

        let favor_votes = &mut proposal.favor_votes;
        let against_votes = &mut proposal.against_votes;

        if (option::is_none(&proposal.end_vote) || current_epoch < *option::borrow(&proposal.end_vote)) {
            // Voting
            assert!(!vector::contains(favor_votes, &voter)
                && !vector::contains(against_votes, &voter), EALREADY_VOTED);
            if (support) {
                vector::push_back(favor_votes, voter);
            }else {
                vector::push_back(against_votes, voter);
            };
        };

        if (option::is_none(&proposal.end_vote) || current_epoch >= *option::borrow(&proposal.end_vote)) {
            // Execute
            let members_num = vector::length(&governance_info.members);
            let favor_votes_num = vector::length(favor_votes);
            if (ensure_two_thirds(members_num, favor_votes_num)) {
                proposal.state = PROPOSAL_SUCCESS;
                event::emit(ChangeState {
                    proposal_id: object::id(proposal),
                    new_state: PROPOSAL_SUCCESS
                });
                return option::some(genesis::create(option::borrow(&governance_info.governance_manager_cap)))
            } else {
                if (option::is_some(&proposal.end_vote)) {
                    proposal.state = PROPOSAL_FAIL;
                    event::emit(ChangeState {
                        proposal_id: object::id(proposal),
                        new_state: PROPOSAL_FAIL
                    });
                };
                return option::none()
            }
        };
        option::none()
    }

    /// Proposals can only be cancelled if they are advertised or expired and the creator of the proposal
    /// can cancel the proposal
    public entry fun cancel_proposal<T: store + drop>(
        proposal: &mut Proposal<T>,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        if (current_epoch < proposal.expired) {
            assert!(proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING, EVOTE_HAS_STARTED);
        };

        let sender = tx_context::sender(ctx);
        assert!(sender == proposal.creator, ENOT_CREATEOR);

        proposal.state = PROPOSAL_CANCEL;
        event::emit(ChangeState {
            proposal_id: object::id(proposal),
            new_state: PROPOSAL_CANCEL
        });
    }

    /// Allow proposal creator to add additional description to proposal
    public entry fun add_description_for_proposal<T: store + drop, V: store>(
        proposal: &mut Proposal<T>,
        desc: V,
        ctx: &mut TxContext
    ) {
        assert!(proposal.creator == tx_context::sender(ctx), ENOT_CREATEOR);
        dynamic_field::add(&mut proposal.id, ProposalDescId {}, desc);
    }


    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let members = vector::empty<address>();
        vector::push_back(&mut members, tx_context::sender(ctx));
        transfer::share_object(GovernanceInfo {
            id: object::new(ctx),
            governance_manager_cap: option::none(),
            active: false,
            announce_delay: 0,
            voting_delay: 0,
            max_delay: 30,
            members,
            his_proposal: vector::empty(),
        });
    }

    #[test_only]
    struct Certificate has store, drop {}


    #[test_only]
    public fun test_active_governance(
        governance: address,
        scenario: &mut Scenario
    ) {
        // init
        {
            init_for_testing(test_scenario::ctx(scenario));
        };

        // active
        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let upgrade_cap = package::test_publish(id_from_address(@dola_protocol), ctx);
            activate_governance(upgrade_cap, &mut governance_info, test_scenario::ctx(scenario));
            assert!(governance_info.active, 0);

            test_scenario::return_shared(governance_info);
        };
    }


    #[test]
    public fun test_update_member() {
        let governance = @0x22;
        let governance_second_member = @0x11;
        let scenario_val = test_scenario::begin(governance);
        let scenario = &mut scenario_val;

        test_active_governance(governance, scenario);

        // add member
        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            create_proposal(&governance_info, Certificate {}, test_scenario::ctx(scenario));
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<Proposal<Certificate>>(scenario);
            let governance_cap = vote_proposal(
                &governance_info,
                Certificate {},
                &mut proposal,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);
            add_member(&governance_cap, &mut governance_info, governance_second_member);
            assert!(vector::length(&governance_info.members) == 2, 0);
            destroy_governance_cap(governance_cap);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info);
        };

        // remove member
        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            create_proposal(&governance_info, Certificate {}, test_scenario::ctx(scenario));
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<Proposal<Certificate>>(scenario);
            let governance_cap = vote_proposal(
                &governance_info,
                Certificate {},
                &mut proposal,
                true,
                test_scenario::ctx(scenario)
            );
            assert!(option::is_none(&governance_cap), 0);
            assert!(proposal.state == PROPOSAL_VOTING_PENDING, 0);
            assert!(*vector::borrow(&proposal.favor_votes, 0) == governance, 0);
            option::destroy_none(governance_cap);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance_second_member);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<Proposal<Certificate>>(scenario);
            let governance_cap = vote_proposal(
                &governance_info,
                Certificate {},
                &mut proposal,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);
            remove_member(&governance_cap, &mut governance_info, governance_second_member);
            assert!(vector::length(&governance_info.members) == 1, 0);
            destroy_governance_cap(governance_cap);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_delay() {
        let governance = @0x22;
        let scenario_val = test_scenario::begin(governance);
        let scenario = &mut scenario_val;

        test_active_governance(governance, scenario);

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            create_proposal(&governance_info, Certificate {}, test_scenario::ctx(scenario));
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<Proposal<Certificate>>(scenario);
            let governance_cap = vote_proposal(
                &governance_info,
                Certificate {},
                &mut proposal,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);
            update_delay(&governance_cap, &mut governance_info, 1, 1, 3);
            assert!(governance_info.max_delay == 3, 0);
            destroy_governance_cap(governance_cap);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_cancel_proposal() {
        let governance = @0x22;
        let scenario_val = test_scenario::begin(governance);
        let scenario = &mut scenario_val;

        test_active_governance(governance, scenario);

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            create_proposal(&governance_info, Certificate {}, test_scenario::ctx(scenario));
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<Proposal<Certificate>>(scenario);
            cancel_proposal(&mut proposal, test_scenario::ctx(scenario));
            assert!(proposal.state == PROPOSAL_CANCEL, 0);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_upgrade() {
        let governance = @0x22;
        let scenario_val = test_scenario::begin(governance);
        let scenario = &mut scenario_val;

        test_active_governance(governance, scenario);

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            create_proposal(&governance_info, Certificate {}, test_scenario::ctx(scenario));
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_genesis = test_scenario::take_shared<GovernanceGenesis>(scenario);
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<Proposal<Certificate>>(scenario);
            let governance_cap = vote_proposal(
                &governance_info,
                Certificate {},
                &mut proposal,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);
            let governance_manager_cap = upgrade(&governance_cap, &mut governance_info);
            genesis::destroy_manager(&mut governance_genesis, governance_manager_cap);
            destroy_governance_cap(governance_cap);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info);
            test_scenario::return_shared(governance_genesis);
        };

        test_scenario::end(scenario_val);
    }
}
