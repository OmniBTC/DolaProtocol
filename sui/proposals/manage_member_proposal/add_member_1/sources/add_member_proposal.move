module add_member_proposal::proposal {
    use std::option;

    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::tx_context::TxContext;
    use std::ascii::String;
    use sui::object;
    use std::ascii;
    use std::vector;
    use sui::address;

    /// Errors

    const ENOT_CREATOR: u64 = 0;

    /// Constant

    // Member address to be added
    const MEMBER_ADDRESS: vector<u8> = x"7d8135c76c23f9dd3f707d1df475ac9b4a0ea7b3a776c22aa4fff25ba9708f8e";

    const GOVERNANCE_INFO: vector<u8> = x"79d7106ea18373fc7542b0849d5ebefc3a9daf8b664a4f82d9b35bbd0c22042d";

    struct ProposalDesc has store {
        // Description of proposal content
        description: String,
        // Params of `vote_porposal`
        vote_porposal: vector<address>
    }

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    public entry fun create_proposal(
        governance_info: &mut GovernanceInfo,
        ctx: &mut TxContext
    ) {
        governance_v1::create_proposal_with_history<Certificate>(governance_info, Certificate {}, ctx);
    }

    public entry fun add_description_for_proposal(
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let description: String = ascii::string(b"Migrate version from v_1_0_3 to v_1_0_4");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));

        let proposal_desc = ProposalDesc {
            description,
            vote_porposal,
        };

        vector::push_back(&mut proposal_desc.vote_porposal, object::id_to_address(&object::id(proposal)));
        governance_v1::add_description_for_proposal<Certificate, ProposalDesc>(proposal, proposal_desc, ctx);
    }


    public entry fun vote_porposal(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            governance_v1::add_member(&cap, governance_info, address::from_bytes(MEMBER_ADDRESS));
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
