module example_proposal::init_lending_storage {
    use lending::storage::StorageAdminCap;
    use governance::governance::{Governance, GovernanceExternalCap, VoteExternalCap};
    use lending::wormhole_adapter::WormholeAdapater;
    use sui::tx_context::TxContext;
    use governance::governance;
    use std::option;

    public entry fun vote_proposal(
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
}
