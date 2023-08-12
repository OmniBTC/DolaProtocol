module register_new_pool_proposal::proposal {
    use std::ascii;
    use std::ascii::String;
    use std::option;
    use std::vector;

    use dola_protocol::dola_address;
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use dola_protocol::pool_manager;
    use dola_protocol::pool_manager::PoolManagerInfo;
    use sui::address;
    use sui::object;
    use sui::tx_context::TxContext;

    /// Errors

    const ENOT_CREATOR: u64 = 0;

    /// Constant

    // Arbitrum circle usdc
    const POOL_ADDRESS: vector<u8> = x"af88d065e77c8cC2239327C5EDb3A432268e5831";

    // Arbitrum dola chain id
    const DOLA_CHAIN_ID: u16 = 23;

    const DOLA_POOL_ID: u16 = 2;

    const POOL_WEIGHT: u256 = 1;

    const GOVERNANCE_INFO: vector<u8> = x"79d7106ea18373fc7542b0849d5ebefc3a9daf8b664a4f82d9b35bbd0c22042d";

    const POOL_MANAGER_INFO: vector<u8> = x"1be839a23e544e8d4ba7fab09eab50626c5cfed80f6a22faf7ff71b814689cfb";

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
        let description: String = ascii::string(b"Add new USDC pool on arbitrum.");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));
        vector::push_back(&mut vote_porposal, address::from_bytes(POOL_MANAGER_INFO));
        vector::push_back(&mut vote_porposal, object::id_to_address(&object::id(proposal)));

        let proposal_desc = ProposalDesc {
            description,
            vote_porposal,
        };

        governance_v1::add_description_for_proposal<Certificate, ProposalDesc>(proposal, proposal_desc, ctx);
    }


    public entry fun vote_porposal(
        governance_info: &mut GovernanceInfo,
        pool_manager_info: &mut PoolManagerInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            let pool = dola_address::create_dola_address(DOLA_CHAIN_ID, POOL_ADDRESS);

            pool_manager::register_pool(&cap, pool_manager_info, pool, DOLA_POOL_ID);
            pool_manager::set_pool_weight(&cap, pool_manager_info, pool, POOL_WEIGHT);
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
