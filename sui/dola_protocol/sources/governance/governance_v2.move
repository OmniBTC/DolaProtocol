// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Voting governance version 2. Draws on the ideas of DAOStack, using governance token voting governance,
/// the number of votes over a certain threshold proposal passed. Future transition from version 1 to version 2
/// Note: when reviewing proposal, make sure that the `certificate` in the proposal will only flow to
/// this contract. It is created to avoid the possibility of unknown contracts gaining access
module dola_protocol::governance_v2 {
    use std::ascii::{Self, String};
    use std::option::{Self, Option};
    use std::type_name::{Self, TypeName};
    use std::vector;

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use dola_protocol::genesis::{Self, GovernanceCap, GovernanceManagerCap};
    use dola_protocol::merge_coins;

    #[test_only]
    use dola_protocol::genesis::GovernanceGenesis;
    #[test_only]
    use dola_protocol::governance_v1;
    #[test_only]
    use sui::test_scenario::{Self, Scenario};

    const U64_MAX: u64 = 0xFFFFFFFFFFFFFFFF;

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

    // The user is not guardians of governance
    const EINVALID_GUARDIANS: u64 = 3;

    // The user is already a guardians of governance
    const EALREADY_GUARDIANS: u64 = 4;

    // The user has not voted
    const ENOT_VOTED: u64 = 5;

    // Voting has not started
    const EVOTE_NOT_STARTED: u64 = 6;

    // Voting has started
    const EVOTE_HAS_STARTED: u64 = 7;

    // Voting has completed
    const EVOTE_HAS_COMPLETED: u64 = 8;

    // Voting has expired
    const EVOTE_HAS_EXPIRED: u64 = 9;

    // The number of tokens staked to create the proposal is too small
    const EINVALID_PROPOSAL_STAKING: u64 = 10;

    // The number of coin merges is not enough
    const EAMOUNT_NOT_ENOUGH: u64 = 11;

    // The number of coin must be zero
    const EAMOUNT_MUST_ZERO: u64 = 12;

    // Staked token books cannot be aligned
    const EINVLID_STAKED_NUM: u64 = 13;

    // Current state cannot claim
    const EINVLID_CLAIM_STATE: u64 = 14;


    struct GovernanceInfo has key {
        id: UID,
        // Gonvernance manager cap
        governance_manager_cap: Option<GovernanceManagerCap>,
        // Governance token type
        governance_coin_type: Option<TypeName>,
        // Guardians
        guardians: vector<address>,
        // Governance active state
        active: bool,
        // Proposal announcement period waiting time
        announce_delay: u64,
        // Vote waiting time
        voting_delay: u64,
        // The maximum duration of proposal.
        // max_delay > voting_delay + announce_delay
        max_delay: u64,
        // The minimum stake amount for the person who creates the proposal
        proposal_minimum_staking: u64,
        // The minimum total number of votes at the end of voting, otherwise the vote is invalid
        voting_minimum_staking: u64,
        // History proposal
        his_proposal: vector<ID>
    }

    struct Proposal<T: store + drop, phantom CoinType> has key {
        id: UID,
        // creator of the proposal
        creator: address,
        // Start time of vote
        start_vote: u64,
        // End time of vote
        end_vote: u64,
        // Expired time of proposal
        expired: u64,
        // Package id of the proposal
        package_id: String,
        // Certificate of proposal
        certificate: T,
        // Staked coin
        staked_coin: Balance<CoinType>,
        // The all favor number
        favor_num: u64,
        // The number of coin that the user favor to stake in the proposal
        favor_votes: Table<address, u64>,
        // The all against number
        against_num: u64,
        // The number of coin that the user against to stake in the proposal
        against_votes: Table<address, u64>,
        // proposal state
        state: u8
    }

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
        let guardians = vector::empty<address>();
        vector::push_back(&mut guardians, tx_context::sender(ctx));
        transfer::share_object(GovernanceInfo {
            id: object::new(ctx),
            governance_manager_cap: option::none(),
            governance_coin_type: option::none(),
            guardians: vector::empty(),
            active: false,
            announce_delay: 0,
            voting_delay: 1,
            max_delay: 30,
            proposal_minimum_staking: 0,
            voting_minimum_staking: 0,
            his_proposal: vector::empty(),
        });
    }

    /// === Initial Functions ===

    /// Activate the current version of governance through governance after v1.
    public fun activate_governance(
        _: &GovernanceCap,
        governance_info: &mut GovernanceInfo,
        governance_coin_type: TypeName,
        governance_manager_cap: GovernanceManagerCap
    ) {
        assert!(!governance_info.active && vector::length(&governance_info.his_proposal) == 0, EHAS_ACTIVE);
        option::fill(&mut governance_info.governance_coin_type, governance_coin_type);
        option::fill(&mut governance_info.governance_manager_cap, governance_manager_cap);
        governance_info.active = true;
    }

    /// === Governance Functions ===

    /// After the upgrade, all current governance guardians will be invalidated.
    public fun upgrade(_: &GovernanceCap, governance_info: &mut GovernanceInfo): GovernanceManagerCap {
        let governance_manager_cap = option::extract(&mut governance_info.governance_manager_cap);
        governance_info.active = false;
        governance_manager_cap
    }

    /// Add guardians through governance.
    public fun add_guardians(_: &GovernanceCap, governance_info: &mut GovernanceInfo, guardians: address) {
        assert!(!vector::contains(&mut governance_info.guardians, &guardians), EALREADY_GUARDIANS);
        vector::push_back(&mut governance_info.guardians, guardians)
    }

    /// Remove guardians through governance.
    public fun remove_guardians(_: &GovernanceCap, governance_info: &mut GovernanceInfo, guardians: address) {
        check_guardians(governance_info, guardians);
        let (_, index) = vector::index_of(&mut governance_info.guardians, &guardians);
        vector::remove(&mut governance_info.guardians, index);
    }

    /// Update minimum staking through governance
    public fun update_minumum_staking(
        _: &GovernanceCap,
        governance_info: &mut GovernanceInfo,
        proposal_minimum_staking: u64,
        voting_minimum_staking: u64
    ) {
        governance_info.proposal_minimum_staking = proposal_minimum_staking;
        governance_info.voting_minimum_staking = voting_minimum_staking;
    }

    /// Update delay through governance
    public fun update_delay(
        _: &GovernanceCap,
        governance_info: &mut GovernanceInfo,
        announce_delay: u64,
        voting_delay: u64,
        max_delay: u64
    ) {
        assert!(voting_delay > 0, EINVALID_DELAY);
        assert!(max_delay > voting_delay + announce_delay, EINVALID_DELAY);
        governance_info.announce_delay = announce_delay;
        governance_info.voting_delay = voting_delay;
        governance_info.max_delay = max_delay;
    }

    /// === Helper Functions ===

    /// Check if the user is a guardians of governance
    public fun check_guardians(governance_info: &GovernanceInfo, guardians: address) {
        assert!(vector::contains(&governance_info.guardians, &guardians), EINVALID_GUARDIANS)
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
    public fun get_proposal_state<T: store + drop, CoinType>(
        proposal: &mut Proposal<T, CoinType>,
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

    /// Destory governance cap
    public fun destroy_governance_cap(
        governance_cap: GovernanceCap
    ) {
        genesis::destroy(governance_cap);
    }

    /// === Entry Functions ===

    /// Record historical proposal information after entering the era of stock governance
    public fun create_proposal_with_history<T: store + drop, CoinType>(
        governance_info: &mut GovernanceInfo,
        certificate: T,
        staked_coins: vector<Coin<CoinType>>,
        staked_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(governance_info.active, ENOT_ACTIVE);

        let staked_coin = merge_coins::merge_coin(staked_coins, staked_amount, ctx);
        assert!(staked_amount >= governance_info.proposal_minimum_staking, EINVALID_PROPOSAL_STAKING);

        let creator = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        let start_vote = current_epoch + governance_info.announce_delay;
        let end_vote = start_vote + governance_info.voting_delay;
        let expired = current_epoch + governance_info.max_delay;

        let favor_votes = table::new<address, u64>(ctx);
        table::add(&mut favor_votes, creator, staked_amount);

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
            staked_coin: coin::into_balance(staked_coin),
            favor_num: staked_amount,
            favor_votes,
            against_num: 0,
            against_votes: table::new<address, u64>(ctx),
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
    public fun create_proposal<T: store + drop, CoinType>(
        governance_info: &GovernanceInfo,
        certificate: T,
        staked_coins: vector<Coin<CoinType>>,
        staked_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(governance_info.active, ENOT_ACTIVE);

        let staked_coin = merge_coins::merge_coin(staked_coins, staked_amount, ctx);
        assert!(staked_amount >= governance_info.proposal_minimum_staking, EINVALID_PROPOSAL_STAKING);

        let creator = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        let start_vote = current_epoch + governance_info.announce_delay;
        let end_vote = start_vote + governance_info.voting_delay;
        let expired = current_epoch + governance_info.max_delay;

        let favor_votes = table::new<address, u64>(ctx);
        table::add(&mut favor_votes, creator, staked_amount);

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
            staked_coin: coin::into_balance(staked_coin),
            favor_num: staked_amount,
            favor_votes,
            against_num: 0,
            against_votes: table::new<address, u64>(ctx),
            state: PROPOSAL_ANNOUNCEMENT_PENDING
        });
        event::emit(CreateProposal {
            proposal_id
        });
    }


    /// Vote for a proposal
    /// `certificate`: The purpose of passing in the certificate is to ensure that the
    /// vote_proposal is only called by the proposal contract
    public fun vote_proposal<T: store + drop, CoinType>(
        governance_info: &GovernanceInfo,
        _certificate: T,
        proposal: &mut Proposal<T, CoinType>,
        staked_coins: vector<Coin<CoinType>>,
        staked_amount: u64,
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

        let favor_votes = &mut proposal.favor_votes;
        let against_votes = &mut proposal.against_votes;
        let staked_coin = merge_coins::merge_coin(staked_coins, staked_amount, ctx);

        if (current_epoch < proposal.end_vote) {
            // Voting
            balance::join(&mut proposal.staked_coin, coin::into_balance(staked_coin));
            if (support) {
                proposal.favor_num = proposal.favor_num + staked_amount;
                let favor_num = staked_amount;
                if (table::contains(favor_votes, voter)) {
                    favor_num = favor_num + table::remove(favor_votes, voter);
                };
                if (table::contains(against_votes, voter)) {
                    let against_num = table::remove(against_votes, voter);
                    proposal.favor_num = proposal.favor_num + against_num;
                    proposal.against_num = proposal.against_num - against_num;
                    favor_num = favor_num + against_num;
                };
                table::add(favor_votes, voter, favor_num);
            }else {
                proposal.against_num = proposal.against_num + staked_amount;
                let against_num = staked_amount;
                if (table::contains(against_votes, voter)) {
                    against_num = against_num + table::remove(against_votes, voter);
                };
                if (table::contains(favor_votes, voter)) {
                    let favor_num = table::remove(favor_votes, voter);
                    proposal.against_num = proposal.against_num + favor_num;
                    proposal.favor_num = proposal.favor_num - favor_num;
                    against_num = against_num + favor_num;
                };
                table::add(against_votes, voter, against_num);
            };
            assert!(
                proposal.favor_num + proposal.against_num == balance::value(&proposal.staked_coin),
                EINVLID_STAKED_NUM
            );
            option::none()
        }else {
            // Execute
            coin::destroy_zero(staked_coin);
            let votes_num = proposal.favor_num + proposal.against_num;
            if (ensure_two_thirds(
                votes_num,
                proposal.favor_num
            ) && votes_num >= governance_info.voting_minimum_staking) {
                proposal.state = PROPOSAL_SUCCESS;
                event::emit(ChangeState {
                    proposal_id: object::id(proposal),
                    new_state: PROPOSAL_SUCCESS
                });
                option::some(genesis::create(option::borrow(&governance_info.governance_manager_cap)))
            } else {
                proposal.state = PROPOSAL_FAIL;
                event::emit(ChangeState {
                    proposal_id: object::id(proposal),
                    new_state: PROPOSAL_FAIL
                });
                option::none()
            }
        }
    }

    /// Proposals can only be cancelled if they are advertised or expired and the creator of the proposal
    /// can cancel the proposal
    public entry fun cancel_proposal<T: store + drop, CoinType>(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<T, CoinType>,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        if (current_epoch < proposal.expired) {
            assert!(proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING, EVOTE_HAS_STARTED);
        };

        let sender = tx_context::sender(ctx);
        check_guardians(governance_info, sender);

        proposal.state = PROPOSAL_CANCEL;
        event::emit(ChangeState {
            proposal_id: object::id(proposal),
            new_state: PROPOSAL_CANCEL
        });
    }


    /// After the proposal ends, get back the staked governance tokens
    public entry fun claim<T: store + drop, CoinType>(
        proposal: &mut Proposal<T, CoinType>,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);

        assert!((proposal.state == PROPOSAL_SUCCESS
            || proposal.state == PROPOSAL_FAIL
            || proposal.state == PROPOSAL_CANCEL
            || current_epoch >= proposal.expired), EINVLID_CLAIM_STATE);

        let sender = tx_context::sender(ctx);
        let favor_votes = &mut proposal.favor_votes;
        let against_votes = &mut proposal.against_votes;

        if (table::contains(favor_votes, sender)) {
            let user_favor_num = table::remove(favor_votes, sender);
            transfer::public_transfer(
                coin::from_balance(balance::split(&mut proposal.staked_coin, user_favor_num), ctx),
                sender
            );
            proposal.favor_num = proposal.favor_num - user_favor_num;
        }else if (table::contains(against_votes, sender)) {
            let user_against_num = table::remove(against_votes, sender);
            transfer::public_transfer(
                coin::from_balance(balance::split(&mut proposal.staked_coin, user_against_num), ctx),
                sender
            );
            proposal.against_num = proposal.against_num - user_against_num;
        }else {
            abort ENOT_VOTED
        }
    }


    #[test_only]
    struct DOLA has drop {}

    #[test_only]
    public fun init_coin(
        members: vector<address>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let i = 0;
        while (i < vector::length(&members)) {
            transfer::public_transfer(
                coin::from_balance(balance::create_for_testing<DOLA>(amount), ctx),
                *vector::borrow(&members, i)
            );
            i = i + 1;
        };
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let guardians = vector::empty<address>();
        vector::push_back(&mut guardians, tx_context::sender(ctx));
        transfer::share_object(GovernanceInfo {
            id: object::new(ctx),
            governance_manager_cap: option::none(),
            governance_coin_type: option::none(),
            guardians: vector::empty(),
            active: false,
            announce_delay: 0,
            voting_delay: 1,
            max_delay: 30,
            proposal_minimum_staking: 0,
            voting_minimum_staking: 0,
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

        // active governance v1
        test_scenario::next_tx(scenario, governance);
        {
            governance_v1::test_active_governance(governance, scenario);
        };

        // upgrade v1 to v2 and active governance v2
        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<governance_v1::GovernanceInfo>(scenario);
            governance_v1::create_proposal(&governance_info, Certificate {}, test_scenario::ctx(scenario));
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info_v1 = test_scenario::take_shared<governance_v1::GovernanceInfo>(scenario);
            let proposal = test_scenario::take_shared<governance_v1::Proposal<Certificate>>(scenario);
            let governance_cap = governance_v1::vote_proposal(
                &mut governance_info_v1,
                Certificate {},
                &mut proposal,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);
            let governance_manager_cap = governance_v1::upgrade(&governance_cap, &mut governance_info_v1);
            let governance_info_v2 = test_scenario::take_shared<GovernanceInfo>(scenario);
            activate_governance(
                &governance_cap,
                &mut governance_info_v2,
                type_name::get<DOLA>(),
                governance_manager_cap
            );
            update_minumum_staking(&governance_cap, &mut governance_info_v2, 100, 1000);
            assert!(governance_info_v2.active, 0);
            assert!(governance_info_v2.voting_minimum_staking == 1000, 0);
            destroy_governance_cap(governance_cap);

            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_info_v1);
            test_scenario::return_shared(governance_info_v2);
        };
    }

    #[test]
    public fun test_update_guardians() {
        let governance = @0x22;
        let governance_second_member = @11;
        let scenario_val = test_scenario::begin(governance);
        let scenario = &mut scenario_val;

        test_active_governance(governance, scenario);


        test_scenario::next_tx(scenario, governance);
        {
            let members = vector::empty<address>();
            vector::push_back(&mut members, governance);
            vector::push_back(&mut members, governance_second_member);
            init_coin(members, 10000, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            let staked_coins = vector::empty<Coin<DOLA>>();
            vector::push_back(&mut staked_coins, governance_coin);

            create_proposal<Certificate, DOLA>(
                &governance_info,
                Certificate {},
                staked_coins,
                100,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            assert!(coin::value(&governance_coin) == 9900, 0);
            transfer::public_transfer(governance_coin, governance);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            let staked_coins = vector::empty<Coin<DOLA>>();
            vector::push_back(&mut staked_coins, governance_coin);
            let proposal = test_scenario::take_shared<Proposal<Certificate, DOLA>>(scenario);
            let governance_cap = vote_proposal<Certificate, DOLA>(
                &governance_info,
                Certificate {},
                &mut proposal,
                staked_coins,
                900,
                true,
                test_scenario::ctx(scenario)
            );
            option::destroy_none(governance_cap);

            test_scenario::return_shared(governance_info);
            test_scenario::return_shared(proposal);
        };

        test_scenario::next_tx(scenario, governance);
        {
            tx_context::increment_epoch_number(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let staked_coins = vector::empty();
            vector::push_back(&mut staked_coins, coin::zero<DOLA>(test_scenario::ctx(scenario)));
            let proposal = test_scenario::take_shared<Proposal<Certificate, DOLA>>(scenario);
            let governance_cap = vote_proposal<Certificate, DOLA>(
                &governance_info,
                Certificate {},
                &mut proposal,
                staked_coins,
                0,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);

            add_guardians(&governance_cap, &mut governance_info, governance_second_member);
            assert!(vector::length(&governance_info.guardians) == 1, 0);
            remove_guardians(&governance_cap, &mut governance_info, governance_second_member);
            assert!(vector::length(&governance_info.guardians) == 0, 0);
            update_delay(&governance_cap, &mut governance_info, 1, 1, 3);
            assert!(governance_info.max_delay == 3, 0);
            claim(&mut proposal, test_scenario::ctx(scenario));

            destroy_governance_cap(governance_cap);
            test_scenario::return_shared(governance_info);
            test_scenario::return_shared(proposal);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            assert!(coin::value(&governance_coin) == 1000, 0);
            transfer::public_transfer(governance_coin, governance);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_upgrade() {
        let governance = @0x22;
        let governance_second_member = @11;
        let scenario_val = test_scenario::begin(governance);
        let scenario = &mut scenario_val;

        test_active_governance(governance, scenario);


        test_scenario::next_tx(scenario, governance);
        {
            let members = vector::empty<address>();
            vector::push_back(&mut members, governance);
            vector::push_back(&mut members, governance_second_member);
            init_coin(members, 10000, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            let staked_coins = vector::empty<Coin<DOLA>>();
            vector::push_back(&mut staked_coins, governance_coin);

            create_proposal<Certificate, DOLA>(
                &governance_info,
                Certificate {},
                staked_coins,
                100,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(governance_info);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            assert!(coin::value(&governance_coin) == 9900, 0);
            transfer::public_transfer(governance_coin, governance);
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let governance_coin = test_scenario::take_from_address<Coin<DOLA>>(scenario, governance);
            let staked_coins = vector::empty<Coin<DOLA>>();
            vector::push_back(&mut staked_coins, governance_coin);
            let proposal = test_scenario::take_shared<Proposal<Certificate, DOLA>>(scenario);
            let governance_cap = vote_proposal<Certificate, DOLA>(
                &governance_info,
                Certificate {},
                &mut proposal,
                staked_coins,
                900,
                true,
                test_scenario::ctx(scenario)
            );
            option::destroy_none(governance_cap);

            test_scenario::return_shared(governance_info);
            test_scenario::return_shared(proposal);
        };

        test_scenario::next_tx(scenario, governance);
        {
            tx_context::increment_epoch_number(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, governance);
        {
            let governance_genesis = test_scenario::take_shared<GovernanceGenesis>(scenario);
            let governance_info = test_scenario::take_shared<GovernanceInfo>(scenario);
            let staked_coins = vector::empty();
            vector::push_back(&mut staked_coins, coin::zero<DOLA>(test_scenario::ctx(scenario)));
            let proposal = test_scenario::take_shared<Proposal<Certificate, DOLA>>(scenario);
            let governance_cap = vote_proposal<Certificate, DOLA>(
                &governance_info,
                Certificate {},
                &mut proposal,
                staked_coins,
                0,
                true,
                test_scenario::ctx(scenario)
            );
            let governance_cap = option::destroy_some(governance_cap);

            let governance_manager_cap = upgrade(&governance_cap, &mut governance_info);
            genesis::destroy_manager(&mut governance_genesis, governance_manager_cap);
            destroy_governance_cap(governance_cap);

            test_scenario::return_shared(governance_info);
            test_scenario::return_shared(proposal);
            test_scenario::return_shared(governance_genesis);
        };

        test_scenario::end(scenario_val);
    }
}
