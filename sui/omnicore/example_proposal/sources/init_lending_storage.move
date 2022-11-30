module example_proposal::init_lending_storage {
    use std::option;

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
