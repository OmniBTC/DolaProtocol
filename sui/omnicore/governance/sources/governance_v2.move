/// Voting governance version 2. Draws on the ideas of DAOStack, using governance token voting governance,
/// the number of votes over a certain threshold proposal passed. Future transition from version 1 to version 2
/// Note: when reviewing proposal, make sure that the `certificate` in the proposal will only flow to
/// this contract. It is created to avoid the possibility of unknown contracts gaining access
module governance::governance_v2 {
    use std::option::{Self, Option};
    use std::vector;

    use governance::genesis::{Self, GovernanceCap, GovernanceManagerCap};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::ascii::String;
    use std::type_name;
    use std::ascii;
    use std::type_name::TypeName;
    use sui::balance::Balance;
    use sui::table::Table;
    use sui::coin::Coin;
    use sui::coin;
    use sui::table;
    use sui::balance;

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

    // The user is not a proposal creator
    const EINVALID_PROPOSAL_STAKING: u64 = 10;

    const ENOT_ENOUGH_AMOUNT: u64 = 10;

    const EMUST_ZERO: u64 = 10;

    const EINVLID_STAKED_NUM: u64 = 10;


    struct GovernanceInfo has key {
        id: UID,
        // Gonvernance manager cap
        governance_manager_cap: Option<GovernanceManagerCap>,
        // Governance token type
        governance_coin_type: Option<TypeName>,
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
        // The all favor numver
        favor_num: u64,
        // The number of coin that the user favor to stake in the proposal
        favor_votes: Table<address, u64>,
        // The all against numver
        against_num: u64,
        // The number of coin that the user against to stake in the proposal
        against_votes: Table<address, u64>,
        // proposal state
        state: u8
    }

    fun init(ctx: &mut TxContext) {
        let members = vector::empty<address>();
        vector::push_back(&mut members, tx_context::sender(ctx));
        transfer::share_object(GovernanceInfo {
            id: object::new(ctx),
            governance_manager_cap: option::none(),
            governance_coin_type: option::none(),
            active: false,
            announce_delay: 0,
            voting_delay: 0,
            max_delay: 30,
            proposal_minimum_staking: 0,
            voting_minimum_staking: 0,
            his_proposal: vector::empty(),
        });
    }

    /// Activate the current version of governance.
    public fun activate_governance(
        governance_info: &mut GovernanceInfo,
        governance_coin_type: TypeName,
        governance_manager_cap: GovernanceManagerCap
    ) {
        assert!(!governance_info.active && vector::length(&governance_info.his_proposal) == 0, EHAS_ACTIVE);
        option::fill(&mut governance_info.governance_coin_type, governance_coin_type);
        option::fill(&mut governance_info.governance_manager_cap, governance_manager_cap);
        governance_info.active = true;
    }

    /// After the upgrade, all current governance members will be invalidated.
    public fun upgrade(_: &GovernanceCap, governance_info: &mut GovernanceInfo): GovernanceManagerCap {
        let governance_manager_cap = option::extract(&mut governance_info.governance_manager_cap);
        governance_info.active = false;
        governance_manager_cap
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

    public fun ensure_two_thirds(votes_num: u64, favor_num: u64): bool {
        let threshold =
            if (votes_num % 3 == 0) {
                votes_num * 2 / 3
            } else {
                votes_num * 2 / 3 + 1
            };
        favor_num >= threshold
    }

    public fun merge_coin<CoinType>(
        coins: vector<Coin<CoinType>>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        let len = vector::length(&coins);
        if (len > 0) {
            vector::reverse(&mut coins);
            let base_coin = vector::pop_back(&mut coins);
            while (!vector::is_empty(&coins)) {
                coin::join(&mut base_coin, vector::pop_back(&mut coins));
            };
            vector::destroy_empty(coins);
            let sum_amount = coin::value(&base_coin);
            let split_amount = amount;
            if (amount == U64_MAX) {
                split_amount = sum_amount;
            };
            assert!(sum_amount >= split_amount, ENOT_ENOUGH_AMOUNT);
            if (coin::value(&base_coin) > split_amount) {
                let split_coin = coin::split(&mut base_coin, split_amount, ctx);
                transfer::transfer(base_coin, tx_context::sender(ctx));
                split_coin
            }else {
                base_coin
            }
        }else {
            vector::destroy_empty(coins);
            assert!(amount == 0, EMUST_ZERO);
            coin::zero<CoinType>(ctx)
        }
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

        let staked_coin = merge_coin(staked_coins, staked_amount, ctx);
        assert!(staked_amount >= governance_info.proposal_minimum_staking, EINVALID_PROPOSAL_STAKING);

        let creator = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        let start_vote = current_epoch + governance_info.announce_delay;
        let end_vote = start_vote + governance_info.voting_delay;
        let expired = current_epoch + governance_info.max_delay;

        let favor_votes = table::new<address, u64>(ctx);
        table::add(&mut favor_votes, creator, staked_amount);

        transfer::share_object(Proposal {
            id: object::new(ctx),
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
    }


    /// Vote for a proposal
    /// `certificate`: The purpose of passing in the certificate is to ensure that the
    /// vote_proposal is only called by the proposal contract
    public fun vote_proposal<T: store + drop, CoinType>(
        governance_info: &mut GovernanceInfo,
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
            proposal.state = PROPOSAL_VOTING_PENDING
        };

        assert!(proposal.state == PROPOSAL_VOTING_PENDING, EVOTE_HAS_COMPLETED);

        let voter = tx_context::sender(ctx);

        let favor_votes = &mut proposal.favor_votes;
        let against_votes = &mut proposal.against_votes;
        let staked_coin = merge_coin(staked_coins, staked_amount, ctx);

        if (current_epoch < proposal.end_vote) {
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
            coin::destroy_zero(staked_coin);
            let votes_num = proposal.favor_num + proposal.against_num;
            if (ensure_two_thirds(
                votes_num,
                proposal.favor_num
            ) && votes_num >= governance_info.voting_minimum_staking) {
                proposal.state = PROPOSAL_SUCCESS;
                option::some(genesis::create(option::borrow(&governance_info.governance_manager_cap)))
            } else {
                proposal.state = PROPOSAL_FAIL;
                option::none()
            }
        }
    }

    /// Proposals can only be cancelled if they are advertised or expired and the creator of the proposal
    /// can cancel the proposal
    public entry fun cancel_proposal<T: store + drop, CoinType>(
        proposal: &mut Proposal<T, CoinType>,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        if (current_epoch < proposal.expired) {
            assert!(proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING, EVOTE_HAS_STARTED);
        };

        let voter = tx_context::sender(ctx);
        assert!(voter == proposal.creator, ENOT_CREATEOR);

        proposal.state = PROPOSAL_CANCEL;
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
        }else if (current_epoch >= proposal.expired) {
            ascii::string(b"EXPIRED")
        }else if (proposal.state == PROPOSAL_ANNOUNCEMENT_PENDING) {
            ascii::string(b"ANNOUNCEMENT_PENDING")
        }else {
            ascii::string(b"VOTING_PENDING")
        }
    }
}
