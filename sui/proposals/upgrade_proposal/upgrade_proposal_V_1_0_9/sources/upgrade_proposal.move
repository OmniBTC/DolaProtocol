module upgrade_proposal::proposal {
    use std::option;

    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::package::{UpgradeReceipt, UpgradeTicket};
    use sui::tx_context::TxContext;
    use std::ascii::String;
    use std::vector;
    use sui::address;
    use std::ascii;
    use sui::object;

    /// The digest of the new contract
    const DIGEST: vector<u8> = x"b022f71b3d152b21c8f06f7651cc835e32cb0f4a1aeff1d68e6d65d84d13c2b2";
    const POLICY: u8 = 0;

    /// Errors
    const ENOT_FINAL_VOTE: u64 = 0;

    const EIS_FINAL_VOTE: u64 = 0;

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

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal_with_history<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun add_description_for_proposal(
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let description: String = ascii::string(b"Upgrade version from v_1_0_8 to v_1_0_9");

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
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_none(&governance_cap), EIS_FINAL_VOTE);
        option::destroy_none(governance_cap)
    }

    public fun vote_proposal_final(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        gov_genesis: &mut GovernanceGenesis,
        ctx: &mut TxContext
    ): UpgradeTicket {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        assert!(option::is_some(&governance_cap), ENOT_FINAL_VOTE);
        let cap = option::extract(&mut governance_cap);
        let ticket = genesis::authorize_upgrade(&cap, gov_genesis, POLICY, DIGEST);
        governance_v1::destroy_governance_cap(cap);
        option::destroy_none(governance_cap);
        ticket
    }

    public fun commit_upgrade(
        gov_genesis: &mut GovernanceGenesis,
        receipt: UpgradeReceipt,
    ) {
        genesis::commit_upgrade(gov_genesis, receipt)
    }
}
