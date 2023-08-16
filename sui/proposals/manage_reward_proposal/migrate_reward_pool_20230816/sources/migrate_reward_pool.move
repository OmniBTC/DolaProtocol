// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module add_reward_pool::proposal {
    use std::option;

    use dola_protocol::governance_v1::{Self, GovernanceInfo, Proposal};
    use dola_protocol::boost;
    use sui::tx_context::TxContext;
    use std::ascii::String;
    use sui::object;
    use std::ascii;
    use std::vector;
    use sui::address;
    use sui::object::UID;
    use sui::balance::Balance;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::balance;
    use dola_protocol::lending_core_storage::Storage;
    use sui::tx_context;

    const SUI_POOL_ID: u16 = 3;

    const WORMHOLE_USDC_POOL_ID: u16 = 8;

    const GOVERNANCE_INFO: vector<u8> = x"79d7106ea18373fc7542b0849d5ebefc3a9daf8b664a4f82d9b35bbd0c22042d";

    const STORAGE: vector<u8> = x"e5a189b1858b207f2cf8c05a09d75bae4271c7a9a8f84a8c199c6896dc7c37e6";


    struct ProposalDesc has store {
        // Description of proposal content
        description: String,
        // Params of `vote_porposal`
        vote_porposal: vector<address>
    }

    struct EscrowReward has key {
        id: UID,
        // Escrow reward
        reward: Balance<SUI>,
        // Creator
        creator: address
    }

    /// To prove that this is a proposal, make sure that the `certificate` in the proposal will only flow to
    /// governance contract.
    struct Certificate has store, drop {}

    fun init(ctx: &mut TxContext) {
        transfer::share_object(
            EscrowReward {
                id: object::new(ctx),
                reward: balance::zero(),
                creator: tx_context::sender(ctx)
            }
        );
    }

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
        let description: String = ascii::string(b"Migrate sui reward pool");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));
        vector::push_back(&mut vote_porposal, address::from_bytes(STORAGE));
        vector::push_back(&mut vote_porposal, object::id_to_address(&object::id(proposal)));

        let proposal_desc = ProposalDesc {
            description,
            vote_porposal,
        };

        governance_v1::add_description_for_proposal<Certificate, ProposalDesc>(proposal, proposal_desc, ctx);
    }


    public entry fun vote_porposal(
        governance_info: &mut GovernanceInfo,
        storage: &mut Storage,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            boost::migrate_reward_pool(&cap, storage, SUI_POOL_ID);
            boost::migrate_reward_pool(&cap, storage, WORMHOLE_USDC_POOL_ID);
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
