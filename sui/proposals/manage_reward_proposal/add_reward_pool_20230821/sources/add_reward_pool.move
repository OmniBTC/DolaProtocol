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
    use sui::coin::Coin;
    use sui::coin;
    use dola_protocol::lending_core_storage::Storage;
    use dola_protocol::lending_codec;
    use sui::tx_context;

    /// Errors

    const ENOT_ENOUGH_REWARD: u64 = 0;

    /// Constants

    // Deposit wormhole usdc reward
    const DEPOSIT_WORMHOLE_USDC: u64 = 547612857142 * 7;

    // Wormhole usdc pool id
    const WORMHOLE_USDC_POOL_ID: u16 = 8;

    // Deposit sui reward
    const DEPOSIT_SUI: u64 = 3160850000000 * 7;

    // Sui pool id
    const SUI_POOL_ID: u16 = 3;

    // 2023-08-21 02:00:00 +UTC
    const START_TIME: u256 = 1692583200;

    // 2023-08-28 02:00:00 +UTC
    const END_TIME: u256 = 1693188000;

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

    public fun all_reward(): u64 {
        DEPOSIT_WORMHOLE_USDC + DEPOSIT_SUI
    }

    public entry fun create_proposal(
        governance_info: &mut GovernanceInfo,
        escrow_reward: &mut EscrowReward,
        reward: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let value = coin::value(&reward);
        assert!(value >= all_reward(), ENOT_ENOUGH_REWARD);
        balance::join(&mut escrow_reward.reward, coin::into_balance(reward));
        governance_v1::create_proposal_with_history<Certificate>(governance_info, Certificate {}, ctx);
    }

    public entry fun add_description_for_proposal(
        proposal: &mut Proposal<Certificate>,
        escrow_reward: &EscrowReward,
        ctx: &mut TxContext
    ) {
        let description: String = ascii::string(b"Add sui reward pool from 2023-08-21 to 2023-08-28");

        let vote_porposal = vector::empty<address>();
        vector::push_back(&mut vote_porposal, address::from_bytes(GOVERNANCE_INFO));
        vector::push_back(&mut vote_porposal, address::from_bytes(STORAGE));
        vector::push_back(&mut vote_porposal, object::id_to_address(&object::id(escrow_reward)));
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
        escrow_reward: &mut EscrowReward,
        proposal: &mut Proposal<Certificate>,
        ctx: &mut TxContext
    ) {
        let governance_cap = governance_v1::vote_proposal(governance_info, Certificate {}, proposal, true, ctx);
        if (option::is_some(&governance_cap)) {
            let cap = option::extract(&mut governance_cap);
            let supply_wormhole_usdc_reward: Coin<SUI> = coin::from_balance(
                balance::split(&mut escrow_reward.reward, DEPOSIT_WORMHOLE_USDC),
                ctx
            );
            let supply_sui_reward: Coin<SUI> = coin::from_balance(
                balance::split(&mut escrow_reward.reward, DEPOSIT_SUI),
                ctx
            );
            boost::create_reward_pool(
                &cap,
                storage,
                START_TIME,
                END_TIME,
                supply_wormhole_usdc_reward,
                WORMHOLE_USDC_POOL_ID,
                lending_codec::get_supply_type(),
                ctx
            );
            boost::create_reward_pool(
                &cap,
                storage,
                START_TIME,
                END_TIME,
                supply_sui_reward,
                SUI_POOL_ID,
                lending_codec::get_supply_type(),
                ctx
            );
            let refund = coin::from_balance(balance::withdraw_all(&mut escrow_reward.reward), ctx);
            transfer::public_transfer(refund, escrow_reward.creator);
            governance_v1::destroy_governance_cap(cap);
        };
        option::destroy_none(governance_cap);
    }
}
