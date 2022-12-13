module example_proposal::init_lending_storage {
    use std::option;

    use oracle::oracle::PriceOracle;

    use app_manager::app_manager::{Self, AppManagerCap, TotalAppInfo};
    use governance::governance::{Self, Governance, GovernanceExternalCap, VoteExternalCap};
    use lending::storage::{StorageAdminCap, Storage};
    use lending::wormhole_adapter::WormholeAdapater;
    use sui::tx_context::TxContext;

    public entry fun vote_storage_cap_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        wormhole_adapater: &mut WormholeAdapater,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<StorageAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<StorageAdminCap>(&mut flash_cap);
            let storage_cap = lending::storage::register_cap_with_admin(external_cap);
            lending::wormhole_adapter::transfer_storage_cap(wormhole_adapater, storage_cap);
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }

    public entry fun vote_set_borrow_rate_factors(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        catalog: String,
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<StorageAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<StorageAdminCap>(&mut flash_cap);
            let storage_cap = lending::storage::register_cap_with_admin(external_cap);
            lending::storage::update_borrow_rate_factors(
                &mut storage_cap,
                storage,
                catalog,
                base_borrow_rate,
                borrow_rate_slope1,
                borrow_rate_slope2,
                optimal_utilization
            );
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }

    public entry fun vote_register_new_reserve_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        oracle: &mut PriceOracle,
        catalog: String,
        treasury: address,
        treasury_factor: u64,
        collateral_coefficient: u64,
        borrow_coefficient: u64,
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<StorageAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<StorageAdminCap>(&mut flash_cap);
            lending::storage::register_new_reserve(
                external_cap,
                storage,
                oracle,
                catalog,
                treasury,
                treasury_factor,
                collateral_coefficient,
                borrow_coefficient,
                base_borrow_rate,
                borrow_rate_slope1,
                borrow_rate_slope2,
                optimal_utilization,
                ctx
            );
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }

    public entry fun vote_app_cap_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<AppManagerCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<AppManagerCap>(&mut flash_cap);
            let app_cap = app_manager::register_cap_with_admin(external_cap, total_app_info, ctx);
            lending::storage::transfer_app_cap(storage, app_cap);
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }
}
