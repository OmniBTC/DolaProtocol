module add_group_proposal::proposal {
    use std::option;

    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::tx_context::TxContext;
    use std::ascii::String;
    use std::ascii;
    use std::vector;
    use sui::address;
    use sui::object;
    use dola_protocol::user_manager;
    use dola_protocol::user_manager::UserManagerInfo;

    const BASE_CHAIN_ID: u16 = 30;

    const EVM_GROUP_ID: u16 = 2;

    // Add LM address
    const MEMBER_ADDRESS: vector<u8> = x"9bab5b2fa325fe2b103fd6a56a93bf91925b269a2dd31ee146b693e5cb9d2901";

    const GOVERNANCE_INFO: vector<u8> = x"ee633dc3fd1218d3bd9703fb9b98e6c8d7fdd8c8bf1ca2645ee40d65fb533a3e";

    const USER_MANAGER_INFO: vector<u8> = x"42ef90066e649215e6ab91399a83e1a5467fd7cc436e8b83adb8743a0efba621";


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
        vector::push_back(&mut vote_porposal, address::from_bytes(USER_MANAGER_INFO));
        vector::push_back(&mut vote_porposal, object::id_to_address(&object::id(proposal)));

        let proposal_desc = ProposalDesc {
            description,
            vote_porposal,
        };

        governance_v1::add_description_for_proposal<Certificate, ProposalDesc>(proposal, proposal_desc, ctx);
    }

    public entry fun vote_porposal(
        governance_info: &mut GovernanceInfo,
        user_manager_info: &mut UserManagerInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            governance_v1::add_member(&cap, governance_info, address::from_bytes(MEMBER_ADDRESS));
            user_manager::register_dola_chain_id(&cap, user_manager_info, BASE_CHAIN_ID, EVM_GROUP_ID);
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap)
    }
}
