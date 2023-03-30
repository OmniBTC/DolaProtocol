module 0x1::remote {
    use std::option::{Self, Option};

    use wormhole::state::State;

    use governance::genesis::GovernanceCap;
    use governance::governance_v1::{Self, GovernanceInfo, Proposal};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use wormhole_adapter_core::wormhole_adapter_core::{Self, CoreState};

    const E_FINISHED_PROPOSAL: u64 = 1;

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    struct ProposalInfo has key {
        id: UID,
        proposal_num: u64,
        proposal_cap: Option<GovernanceCap>
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(ProposalInfo {
            id: object::new(ctx),
            proposal_num: 1,
            proposal_cap: option::none()
        })
    }

    fun get_proposal_cap(proposal_info: &mut ProposalInfo): &GovernanceCap {
        proposal_info.proposal_num = proposal_info.proposal_num - 1;
        assert!(proposal_info.proposal_num > 0, E_FINISHED_PROPOSAL);
        option::borrow(&proposal_info.proposal_cap)
    }

    fun destroy_cap(proposal_info: &mut ProposalInfo) {
        if (proposal_info.proposal_num == 0) {
            let proposal_cap = option::extract(&mut proposal_info.proposal_cap);
            governance_v1::destroy_governance_cap(proposal_cap);
        }
    }

    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext) {
        governance_v1::create_proposal<Certificate>(governance_info, Certificate {}, ctx)
    }

    public entry fun vote_porposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        proposal_info: &mut ProposalInfo,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            option::fill(&mut proposal_info.proposal_cap, cap);
        };
        option::destroy_none(governance_cap)
    }


    public entry fun register_remote_bridge(
        proposal_info: &mut ProposalInfo,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
        wormhole_emitter_address: vector<u8>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::register_remote_bridge(
            governance_cap,
            core_state,
            wormhole_emitter_chain,
            wormhole_emitter_address
        );

        destroy_cap(proposal_info);
    }

    public entry fun delete_remote_bridge(
        proposal_info: &mut ProposalInfo,
        core_state: &mut CoreState,
        wormhole_emitter_chain: u16,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::delete_remote_bridge(
            governance_cap,
            core_state,
            wormhole_emitter_chain
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_register_owner(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);
        wormhole_adapter_core::remote_register_owner(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_register_spender(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::remote_register_spender(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_delete_owner(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::remote_delete_owner(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }

    public entry fun remote_delete_spender(
        proposal_info: &mut ProposalInfo,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
    ) {
        let governance_cap = get_proposal_cap(proposal_info);

        wormhole_adapter_core::remote_delete_spender(
            governance_cap,
            wormhole_state,
            core_state,
            dola_chain_id,
            dola_contract,
            wormhole_message_fee
        );

        destroy_cap(proposal_info);
    }
}
