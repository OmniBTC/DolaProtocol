module example_proposal::init_user_manager {
    use dola_types::types::convert_external_address_to_dola;
    use user_manager::user_manager::{Self, UserManagerInfo};
    use wormhole_bridge::bridge_core::{Self, CoreState};

    public entry fun init_user_manager_cap_for_bridge(core_state: &mut CoreState) {
        let user_manager_cap = user_manager::register_cap();
        bridge_core::transfer_user_manager_cap(core_state, user_manager_cap);
    }

    public entry fun register_dola_user(user_manager: &mut UserManagerInfo, user: vector<u8>) {
        let user_manager_cap = user_manager::register_cap();
        user_manager::register_dola_user_id(&user_manager_cap, user_manager, convert_external_address_to_dola(user));
    }
}
