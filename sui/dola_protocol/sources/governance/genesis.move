// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::genesis {
    use std::ascii::into_bytes;
    use std::type_name;
    use std::vector;

    use sui::dynamic_field;
    use sui::object::{Self, UID, ID};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer;
    use sui::tx_context::TxContext;

    friend dola_protocol::governance_v1;

    const E_EXIST_PACKAGE: u64 = 0;

    const E_INVALID_OLD_VERSION: u64 = 1;

    const E_SAME_VERSION: u64 = 2;

    const E_TYPE_NOT_ALLOWED: u64 = 3;

    const E_NOT_LATEST_VERISON: u64 = 4;

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

    /// Version key
    struct Version has store, drop, copy {}

    /// Version 1.0.0
    struct Version_1_0_0 has store, drop, copy {}

    /// Version 1.0.1
    struct Version_1_0_1 has store, drop, copy {}

    public fun get_version_1_0_1(): Version_1_0_1 {
        Version_1_0_1 {}
    }

    /// Add a new version structure when upgrading, and upgrade
    /// the version through version migration.
    ///
    /// ```
    /// struct Version_1_0_1 has store, drop, copy {}
    ///
    /// public fun get_version_1_0_1(): Version_1_0_1 {
    ///     Version_1_0_1 {}
    /// }
    /// ```

    /// Check current version
    /// Note: Update the function to set the version limit.
    public fun check_latest_version(genesis: &GovernanceGenesis) {
        assert!(
            dynamic_field::exists_with_type<Version, Version_1_0_1>(&genesis.id, Version {}),
            E_NOT_LATEST_VERISON
        );
    }

    /// === Friend Functions ===
    public(friend) fun init_genesis(upgrade_cap: UpgradeCap, ctx: &mut TxContext): GovernanceManagerCap {
        let governance_genesis = GovernanceGenesis {
            id: object::new(ctx),
            upgrade_cap,
            manager_ids: vector::empty()
        };
        let governance_manager_cap = GovernanceManagerCap {
            id: object::new(ctx)
        };

        // Set current version
        dynamic_field::add(&mut governance_genesis.id, Version {}, Version_1_0_0 {});

        vector::push_back(&mut governance_genesis.manager_ids, object::id(&governance_manager_cap));
        transfer::share_object(governance_genesis);
        governance_manager_cap
    }

    /// === Governance Functions ===

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

    public fun migrate_version<OldVersion: store + drop, NewVersion: store + drop>(
        _: &GovernanceCap,
        genesis: &mut GovernanceGenesis,
        new_version: NewVersion,
    ) {
        assert!(
            dynamic_field::exists_with_type<Version, OldVersion>(&mut genesis.id, Version {}),
            E_INVALID_OLD_VERSION
        );

        let _: OldVersion = dynamic_field::remove(&mut genesis.id, Version {});

        let new_type = type_name::get<NewVersion>();

        assert!(new_type != type_name::get<OldVersion>(), E_SAME_VERSION);

        // Also make sure `New` originates from this module.
        let module_name = into_bytes(type_name::get_module(&new_type));
        assert!(module_name == b"genesis", E_TYPE_NOT_ALLOWED);

        // Finally add the new version.
        dynamic_field::add(&mut genesis.id, Version {}, new_version);
    }

    /// === Helper Functions ===

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


    #[test_only]
    public fun register_governance_cap_for_testing(): GovernanceCap {
        GovernanceCap {}
    }
}
