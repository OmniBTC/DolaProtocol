module set_reserve_proposal::proposal {
    use std::ascii;
    use std::ascii::String;
    use std::option;
    use std::vector;

    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::address;
    use sui::object;
    use sui::tx_context::TxContext;
    use dola_protocol::lending_core_storage;
    use dola_protocol::lending_core_storage::Storage;

    /// Fix sui ceiling

    /// Constant

    const SUI_SUPPLY_CEILING: u256 = 500000000000000;

    const SUI_POOL_ID: u16 = 3;

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
        let description: String = ascii::string(b"Fix sui supply ceiling.");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));
        vector::push_back(&mut vote_porposal, object::id_to_address(&object::id(proposal)));

        let proposal_desc = ProposalDesc {
            description,
            vote_porposal,
        };

        governance_v1::add_description_for_proposal<Certificate, ProposalDesc>(proposal, proposal_desc, ctx);
    }


    public entry fun vote_porposal(
        storage: &mut Storage,
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);

            lending_core_storage::set_supply_cap_ceiling(
                &cap,
                storage,
                SUI_POOL_ID,
                SUI_SUPPLY_CEILING
            );

            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
