module example_proposal::init_user_manager {
    use std::option;

    use governance::governance::{Self, VoteExternalCap, Governance, GovernanceExternalCap};
    use sui::tx_context::TxContext;
    use user_manager::user_manager::{Self, UserManagerAdminCap};
    use wormhole_bridge::bridge_core::{Self, CoreState};

    public entry fun vote_user_manager_cap_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        core_state: &mut CoreState,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<UserManagerAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<UserManagerAdminCap>(&mut flash_cap);
            let user_manager_cap = user_manager::register_cap_with_admin(external_cap);
            bridge_core::transfer_user_manager_cap(core_state, user_manager_cap);
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }
}
