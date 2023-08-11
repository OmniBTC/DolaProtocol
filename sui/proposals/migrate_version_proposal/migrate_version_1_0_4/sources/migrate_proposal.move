module migrate_version_proposal::proposal {
    use std::option;

    use dola_protocol::genesis::{Self, GovernanceGenesis, Version_1_0_3, Version_1_0_4};
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::tx_context::TxContext;
    use std::ascii::String;
    use sui::transfer;
    use sui::object;
    use sui::object::UID;
    use std::ascii;
    use std::vector;
    use sui::address;
    use sui::tx_context;

    /// Errors

    const ENOT_CREATOR: u64 = 0;

    struct ProposalInfo has key {
        id: UID,
        // Description of proposal content
        description: String,
        // Params of `create_proposal`
        create_proposal: vector<address>,
        // Params of `vote_porposal`
        vote_porposal: vector<address>,
        // Whether `create_proposal` has been executed
        is_create_proposal: bool,
        // Creator of the proposal
        creator: address,
    }

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    fun init(ctx: &mut TxContext) {
        let description: String = ascii::string(b"Migrate version from v_1_0_3 to v_1_0_4");
        let governance_info: address = address::from_bytes(
            x"79d7106ea18373fc7542b0849d5ebefc3a9daf8b664a4f82d9b35bbd0c22042d"
        );
        let gov_genesis: address = address::from_bytes(
            x"42ef90066e649215e6ab91399a83e1a5467fd7cc436e8b83adb8743a0efba621"
        );
        let create_proposal = vector::empty<address>();
        vector::push_back(&mut create_proposal, governance_info);

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, governance_info);
        vector::push_back(&mut vote_porposal, gov_genesis);

        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        let proposal_info = ProposalInfo {
            id: uid,
            description,
            create_proposal,
            vote_porposal,
            is_create_proposal: false,
            creator: tx_context::sender(ctx)
        };

        vector::push_back(&mut proposal_info.create_proposal, object::id_to_address(&id));

        transfer::share_object(proposal_info);
    }

    public entry fun create_proposal(
        governance_info: &mut GovernanceInfo,
        proposal_info: &mut ProposalInfo,
        ctx: &mut TxContext
    ) {
        assert!(proposal_info.creator == tx_context::sender(ctx), ENOT_CREATOR);

        // todo! The next upgrade needs to allow reading current proposal from governance_info
        governance_v1::create_proposal_with_history<Certificate>(governance_info, Certificate {}, ctx)
    }

    // todo! Future DEPRECATED
    public entry fun add_vote_porposal(
        proposal_info: &mut ProposalInfo,
        proposal: &Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        assert!(proposal_info.creator == tx_context::sender(ctx), ENOT_CREATOR);

        vector::push_back(&mut proposal_info.vote_porposal, object::id_to_address(&object::id(proposal)));
    }

    public entry fun vote_porposal(
        governance_info: &GovernanceInfo,
        gov_genesis: &mut GovernanceGenesis,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            let new_version = genesis::get_version_1_0_4();
            genesis::migrate_version<Version_1_0_3, Version_1_0_4>(&cap, gov_genesis, new_version);
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
