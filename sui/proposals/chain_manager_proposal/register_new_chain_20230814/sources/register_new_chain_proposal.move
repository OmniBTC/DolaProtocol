module register_new_chain_proposal::proposal {
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
    use dola_protocol::wormhole_adapter_core;
    use dola_protocol::wormhole_adapter_core::CoreState;

    use wormhole::state::State;
    use sui::clock::Clock;
    use sui::coin;
    use sui::sui::SUI;

    /// Add Base Chain

    /// Constant

    const WORMHOLE_EMITTER_CHAIN: u16 = 30;

    const WORMHOLE_EMITTER_ADDRESS: vector<u8> = x"0000000000000000000000000F4aedfB8DA8aF176DefF282DA86EBbe3A0EA19e";

    // Base token address
    const ETH_POOL_ADDRESS: vector<u8> = x"0000000000000000000000000000000000000000";

    const USDC_POOL_ADDRESS: vector<u8> = x"d9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA";

    // Bse token pool id
    const ETH_POOL_ID: u16 = 4;

    const USDC_POOL_ID: u16 = 2;

    // Bse token pool weight
    const ETH_POOL_WEIGHT: u256 = 1;

    const USDC_POOL_WEIGHT: u256 = 1;

    // Base dola chain id
    const DOLA_CHAIN_ID: u16 = 30;

    const WORMHOLE_STATE: vector<u8> = x"aeab97f96cf9877fee2883315d459552b2b921edc16d7ceac6eab944dd88919c";

    const WORMHOLE_CORE_STATE: vector<u8> = x"ffee67f1fc55a72caab7d150abef55625ac6420ca43c5798f5d52db31fb800a7";

    const GOVERNANCE_INFO: vector<u8> = x"79d7106ea18373fc7542b0849d5ebefc3a9daf8b664a4f82d9b35bbd0c22042d";

    const POOL_MANAGER_INFO: vector<u8> = x"1be839a23e544e8d4ba7fab09eab50626c5cfed80f6a22faf7ff71b814689cfb";

    const CLOCK: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000006";

    const RELAYER_ADDRESS: vector<u8> = x"252CDE02Ec05bB96381FeC47DCc8C58c49499681";

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
        let description: String = ascii::string(b"Add base chain.");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));
        vector::push_back(&mut vote_porposal, address::from_bytes(POOL_MANAGER_INFO));
        vector::push_back(&mut vote_porposal, address::from_bytes(WORMHOLE_STATE));
        vector::push_back(&mut vote_porposal, address::from_bytes(WORMHOLE_CORE_STATE));
        vector::push_back(&mut vote_porposal, address::from_bytes(CLOCK));
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
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        clock: &Clock,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);

            // Register remote bridge
            wormhole_adapter_core::register_remote_bridge(
                &cap,
                core_state,
                WORMHOLE_EMITTER_CHAIN,
                WORMHOLE_EMITTER_ADDRESS
            );

            // Register eth
            let pool = dola_address::create_dola_address(DOLA_CHAIN_ID, ETH_POOL_ADDRESS);
            pool_manager::register_pool(&cap, pool_manager_info, pool, ETH_POOL_ID);
            pool_manager::set_pool_weight(&cap, pool_manager_info, pool, ETH_POOL_WEIGHT);

            // Register usdc
            let pool = dola_address::create_dola_address(DOLA_CHAIN_ID, USDC_POOL_ADDRESS);
            pool_manager::register_pool(&cap, pool_manager_info, pool, USDC_POOL_ID);
            pool_manager::set_pool_weight(&cap, pool_manager_info, pool, USDC_POOL_WEIGHT);

            // Add relayer
            wormhole_adapter_core::remote_add_relayer(
                &cap,
                wormhole_state,
                core_state,
                DOLA_CHAIN_ID,
                RELAYER_ADDRESS,
                coin::zero<SUI>(ctx),
                clock,
            );

            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
