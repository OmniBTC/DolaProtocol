// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::genesis {
    use std::vector;

    use sui::object::{Self, UID, ID};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer;
    use sui::tx_context::TxContext;

    friend dola_protocol::governance_v1;

    const E_EXIST_PACKAGE: u64 = 0;

    /// Governance rights struct, responsible for governing all modules of Dola protocol.
    struct GovernanceCap {}

    /// Used to create and destroy `GovernanceCap`.
    /// `GovernanceManagerCap` is hosted for specific voting modules (v1, v2...) ,
    /// to help with possible future upgrades of the voting module itself.
    struct GovernanceManagerCap has key, store {
        id: UID
    }

    /// Record the existing `GovernanceManagerCap` object.
    struct GovernanceGenesis has key {
        id: UID,
        upgrade_cap: UpgradeCap,
        manager_ids: vector<ID>,
    }

    public(friend) fun new(upgrade_cap: UpgradeCap, ctx: &mut TxContext): GovernanceManagerCap {
        let governance_genesis = GovernanceGenesis {
            id: object::new(ctx),
            upgrade_cap,
            manager_ids: vector::empty()
        };
        let governance_manager_cap = GovernanceManagerCap {
            id: object::new(ctx)
        };
        vector::push_back(&mut governance_genesis.manager_ids, object::id(&governance_manager_cap));
        transfer::share_object(governance_genesis);
        governance_manager_cap
    }

    public fun create(_: &GovernanceManagerCap): GovernanceCap {
        GovernanceCap {}
    }

    public fun destroy(governance_cap: GovernanceCap) {
        let GovernanceCap {} = governance_cap;
    }

    public fun destroy_manager(
        governance_genesis: &mut GovernanceGenesis,
        governance_manager_cap: GovernanceManagerCap
    ) {
        let manager_id = object::id(&governance_manager_cap);
        let (_, index) = vector::index_of(&governance_genesis.manager_ids, &manager_id);
        vector::remove(&mut governance_genesis.manager_ids, index);
        let GovernanceManagerCap { id } = governance_manager_cap;
        object::delete(id);
    }

    /// Get the governance_cap through the proposal, return to the UpgradeTicket after
    /// the proposal is passed, and upgrade the contract in the programmable transaction.
    public fun authorize_upgrade(
        _: &GovernanceCap,
        genesis: &mut GovernanceGenesis,
        policy: u8,
        digest: vector<u8>
    ): UpgradeTicket {
        package::authorize_upgrade(&mut genesis.upgrade_cap, policy, digest)
    }

    /// Consume an `UpgradeReceipt` to update its `UpgradeCap`, finalizing
    /// the upgrade.
    public fun commit_upgrade(
        genesis: &mut GovernanceGenesis,
        receipt: UpgradeReceipt,
    ) {
        package::commit_upgrade(&mut genesis.upgrade_cap, receipt);
    }

    #[test_only]
    public fun register_governance_cap_for_testing(): GovernanceCap {
        GovernanceCap {}
    }
}
