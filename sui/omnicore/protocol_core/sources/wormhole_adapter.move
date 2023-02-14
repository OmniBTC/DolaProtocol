module protocol_core::protocol_wormhole_adapter {
    use std::option::{Self, Option};

    use protocol_core::message_types::{Self, binding_type_id, unbinding_type_id};
    use sui::object::UID;
    use user_manager::user_manager::{Self, UserManagerCap, UserManagerInfo};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    const EINVALID_APPID: u64 = 0;
    const EINVALID_CALLTYPE: u64 = 1;

    struct WormholeAdapter has key {
        id: UID,
        user_manager_cap: Option<UserManagerCap>,
    }

    public entry fun binding_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        user_binding: &mut WormholeAdapter,
        core_state: &mut CoreState,
        vaa: vector<u8>
    ) {
        let app_payload = bridge_core::receive_protocol_message(wormhole_state, core_state, vaa);
        let (app_id, user, bind_address, call_type) = user_manager::decode_binding(app_payload);
        assert!(app_id == message_types::app_id(), EINVALID_APPID);
        assert!(call_type == binding_type_id(), EINVALID_CALLTYPE);

        if (user == bind_address) {
            user_manager::register_dola_user_id(
                option::borrow(&user_binding.user_manager_cap),
                user_manager_info,
                user
            );
        } else {
            user_manager::binding_user_address(
                option::borrow(&user_binding.user_manager_cap),
                user_manager_info,
                user,
                bind_address
            );
        };
    }

    public entry fun unbinding_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        user_binding: &mut WormholeAdapter,
        core_state: &mut CoreState,
        vaa: vector<u8>
    ) {
        let app_payload = bridge_core::receive_protocol_message(wormhole_state, core_state, vaa);
        let (app_id, user, unbind_address, call_type) = user_manager::decode_unbinding(app_payload);
        assert!(app_id == message_types::app_id(), EINVALID_APPID);
        assert!(call_type == unbinding_type_id(), EINVALID_CALLTYPE);

        user_manager::unbinding_user_address(
            option::borrow(&user_binding.user_manager_cap),
            user_manager_info,
            user,
            unbind_address
        );
    }
}