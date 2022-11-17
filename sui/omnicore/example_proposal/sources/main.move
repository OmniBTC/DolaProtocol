module example_proposal::main {
    use governance::governance::{Governance, GovernanceExternalCap, VoteExternalCap};
    use sui::tx_context::TxContext;
    use governance::governance;

    use std::option;
    use pool_manager::pool_manager;
    use pool_manager::pool_manager::PoolManagerAdminCap;
    use wormhole_bridge::bridge_core;
    use wormhole_bridge::bridge_core::CoreState;

    public entry fun vote_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        core_state: &mut CoreState,
        ctx: &mut TxContext)
    {
        let flash_cap = governance::vote_external_cap<PoolManagerAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<PoolManagerAdminCap>(&mut flash_cap);
            let pool_manager_cap = pool_manager::register_cap_with_admin(external_cap);
            bridge_core::transfer_pool_manage_cap(core_state, pool_manager_cap);
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }
}
