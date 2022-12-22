module example_proposal::init_pool_manager {
    use std::ascii::string;
    use std::option;

    use dola_types::types::create_dola_address;
    use governance::governance::{Self, Governance, GovernanceExternalCap, VoteExternalCap};
    use pool_manager::pool_manager::{Self, PoolManagerAdminCap, register_pool, PoolManagerInfo};
    use sui::tx_context::TxContext;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    public entry fun vote_pool_manager_cap_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        core_state: &mut CoreState,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<PoolManagerAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<PoolManagerAdminCap>(&mut flash_cap);
            let pool_manager_cap = pool_manager::register_cap_with_admin(external_cap);
            bridge_core::transfer_pool_manager_cap(core_state, pool_manager_cap);
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }

    public entry fun vote_register_new_pool_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        ctx: &mut TxContext
    ) {
        let flash_cap = governance::vote_external_cap<PoolManagerAdminCap>(gov, governance_external_cap, vote, ctx);

        if (option::is_some(&flash_cap)) {
            let external_cap = governance::borrow_external_cap<PoolManagerAdminCap>(&mut flash_cap);
            let pool_manager_cap = pool_manager::register_cap_with_admin(external_cap);
            let pool = create_dola_address(pool_dola_chain_id, pool_dola_address);

            register_pool(&pool_manager_cap, pool_manager_info, pool, string(dola_pool_name), dola_pool_id, ctx);
        };

        governance::external_cap_destroy(governance_external_cap, vote, flash_cap);
    }
}
