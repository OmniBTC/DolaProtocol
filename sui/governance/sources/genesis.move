// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module governance::genesis {
    use std::vector;

    use dola_types::dola_contract::{Self, DolaContract};
    use sui::object::{Self, UID, ID};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    friend governance::governance_v1;

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
        // dola contract id -> upgrade cap
        dola_contracts: Table<u256, UpgradeCap>
    }


    fun init(ctx: &mut TxContext) {
        transfer::share_object(GovernanceGenesis {
            id: object::new(ctx),
            manager_ids: vector::empty()
        });
        transfer::share_object(GovernanceContracts {
            id: object::new(ctx),
            dola_contracts: table::new(ctx)
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

    /// Add the upgrade capability of the contract to governance.
    public fun join_dola_contract(
        gov_contracts: &mut GovernanceContracts,
        dola_contract: &DolaContract,
        upgrade_cap: UpgradeCap
    ) {
        let dola_contract_id = dola_contract::get_dola_contract_id(dola_contract);
        assert!(table::contains(&gov_contracts.dola_contracts, dola_contract_id), E_EXIST_PACKAGE);
        table::add(&mut gov_contracts.dola_contracts, dola_contract_id, upgrade_cap);
    }

    /// Get the governance_cap through the proposal, return to the UpgradeTicket after
    /// the proposal is passed, and upgrade the contract in the programmable transaction.
    public fun authorize_upgrade(
        _: &GovernanceCap,
        gov_contracts: &mut GovernanceContracts,
        dola_contract_id: u256,
        policy: u8,
        digest: vector<u8>
    ): UpgradeTicket {
        let cap = table::borrow_mut(&mut gov_contracts.dola_contracts, dola_contract_id);
        package::authorize_upgrade(cap, policy, digest)
    }

    /// Consume an `UpgradeReceipt` to update its `UpgradeCap`, finalizing
    /// the upgrade.
    public fun commit_upgrade(
        gov_contracts: &mut GovernanceContracts,
        dola_contract_id: u256,
        receipt: UpgradeReceipt,
    ) {
        let cap = table::borrow_mut(&mut gov_contracts.dola_contracts, dola_contract_id);
        package::commit_upgrade(cap, receipt)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun register_governance_cap_for_testing(): GovernanceCap {
        GovernanceCap {}
    }
}
