// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::genesis {
    use std::vector;

    use sui::object::{Self, UID, ID};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::table::{Self, Table};
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
        manager_ids: vector<ID>
    }

    /// Manage all contracts' upgrade cap
    struct GovernanceContracts has key {
        id: UID,
        // pacakge id -> upgrade cap
        packages: Table<address, UpgradeCap>
    }


    fun init(ctx: &mut TxContext) {
        transfer::share_object(GovernanceGenesis {
            id: object::new(ctx),
            manager_ids: vector::empty()
        });
        transfer::share_object(GovernanceContracts {
            id: object::new(ctx),
            packages: table::new(ctx)
        })
    }

    public(friend) fun new(governance_genesis: &mut GovernanceGenesis, ctx: &mut TxContext): GovernanceManagerCap {
        let governance_manager_cap = GovernanceManagerCap {
            id: object::new(ctx)
        };
        vector::push_back(&mut governance_genesis.manager_ids, object::id(&governance_manager_cap));
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

    /// Batch add the upgrade capability of the contract to governance.
    public entry fun batch_add_upgrade_cap(
        governance_contracts: &mut GovernanceContracts,
        upgrade_caps: vector<UpgradeCap>
    ) {
        while (!vector::is_empty(&upgrade_caps)) {
            let upgrade_cap = vector::pop_back(&mut upgrade_caps);
            add_upgrade_cap(governance_contracts, upgrade_cap);
        };
        vector::destroy_empty(upgrade_caps);
    }

    /// Add the upgrade capability of the contract to governance.
    public fun add_upgrade_cap(
        governance_contracts: &mut GovernanceContracts,
        upgrade_cap: UpgradeCap
    ) {
        let package_id = object::id_to_address(&package::upgrade_package(&upgrade_cap));
        assert!(!table::contains(&governance_contracts.packages, package_id), E_EXIST_PACKAGE);
        table::add(&mut governance_contracts.packages, package_id, upgrade_cap);
    }

    /// Get the governance_cap through the proposal, return to the UpgradeTicket after
    /// the proposal is passed, and upgrade the contract in the programmable transaction.
    public fun authorize_upgrade(
        _: &GovernanceCap,
        governance_contracts: &mut GovernanceContracts,
        package_id: address,
        policy: u8,
        digest: vector<u8>
    ): UpgradeTicket {
        let cap = table::borrow_mut(&mut governance_contracts.packages, package_id);
        package::authorize_upgrade(cap, policy, digest)
    }

    /// Consume an `UpgradeReceipt` to update its `UpgradeCap`, finalizing
    /// the upgrade.
    public fun commit_upgrade(
        governance_contracts: &mut GovernanceContracts,
        package_id: address,
        receipt: UpgradeReceipt,
    ) {
        let cap = table::remove(&mut governance_contracts.packages, package_id);
        let new_package_id = object::id_to_address(&package::receipt_package(&receipt));
        package::commit_upgrade(&mut cap, receipt);
        table::add(&mut governance_contracts.packages, new_package_id, cap);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        transfer::share_object(GovernanceGenesis {
            id: object::new(ctx),
            manager_ids: vector::empty()
        });
        transfer::share_object(GovernanceContracts {
            id: object::new(ctx),
            packages: table::new(ctx)
        })
    }

    #[test_only]
    public fun register_governance_cap_for_testing(): GovernanceCap {
        GovernanceCap {}
    }
}
