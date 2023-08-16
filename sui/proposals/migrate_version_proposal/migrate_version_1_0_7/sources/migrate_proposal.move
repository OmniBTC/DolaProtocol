module migrate_version_proposal::proposal {
    use std::option;

    use dola_protocol::genesis::{Self, GovernanceGenesis, Version_1_0_7, Version_1_0_8};
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::tx_context::TxContext;
    use std::ascii::String;
    use std::ascii;
    use std::vector;
    use sui::address;
    use sui::object;

    /// Errors

    const GOVERNANCE_INFO: vector<u8> = x"79d7106ea18373fc7542b0849d5ebefc3a9daf8b664a4f82d9b35bbd0c22042d";

    const GOVERNANCE_GENESIS: vector<u8> = x"42ef90066e649215e6ab91399a83e1a5467fd7cc436e8b83adb8743a0efba621";


    struct ProposalDesc has store {
        // Description of proposal content
        description: String,
        // Params of `vote_porposal`
        vote_porposal: vector<address>
    }

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}


    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal_with_history<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun add_description_for_proposal(
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let description: String = ascii::string(b"Migrate version from v_1_0_7 to v_1_0_8");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_GENESIS));
        vector::push_back(&mut vote_porposal, object::id_to_address(&object::id(proposal)));

        let proposal_desc = ProposalDesc {
            description,
            vote_porposal,
        };

        governance_v1::add_description_for_proposal<Certificate, ProposalDesc>(proposal, proposal_desc, ctx);
    }

    public entry fun vote_porposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        gov_genesis: &mut GovernanceGenesis,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            let new_version = genesis::get_version_1_0_8();
            genesis::migrate_version<Version_1_0_7, Version_1_0_8>(&cap, gov_genesis, new_version);
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap)
    }
}
