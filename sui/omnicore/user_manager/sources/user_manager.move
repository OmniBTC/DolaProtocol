module user_manager::user_manager {
    use std::vector;

    use dola_types::types::{DolaAddress, encode_dola_address, decode_dola_address};
    use governance::governance::GovernanceCap;
    use serde::serde::{serialize_u16, serialize_vector, deserialize_u16, vector_slice, serialize_u8, deserialize_u8};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const ENOT_EXIST_USER: u64 = 0;

    const EALREADY_EXIST_USER: u64 = 1;

    const EDUPLICATED_BINDING: u64 = 2;

    const EINVALID_LENGTH: u64 = 3;

    const ETOO_FEW_ADDRESSES: u64 = 4;

    // todo: fix message type
    const BINDING: u8 = 5;

    const UNBINDING: u8 = 6;

    struct UserManagerInfo has key, store {
        id: UID,
        user_address_catalog: UserAddressCatalog
    }

    struct UserAddressCatalog has store {
        user_address_to_user_id: Table<DolaAddress, u64>,
        user_id_to_addresses: Table<u64, vector<DolaAddress>>
    }

    struct UserManagerCap has store, drop {}

    fun init(ctx: &mut TxContext) {
        transfer::share_object(UserManagerInfo {
            id: object::new(ctx),
            user_address_catalog: UserAddressCatalog {
                user_address_to_user_id: table::new(ctx),
                user_id_to_addresses: table::new(ctx)
            }
        })
    }

    public fun register_cap_with_governance(_: &GovernanceCap): UserManagerCap {
        UserManagerCap {}
    }

    public fun is_dola_user(user_manager: &mut UserManagerInfo, user: DolaAddress): bool {
        let user_catalog = &mut user_manager.user_address_catalog;
        table::contains(&mut user_catalog.user_address_to_user_id, user)
    }

    public fun get_dola_user_id(user_manager: &mut UserManagerInfo, user: DolaAddress): u64 {
        let user_catalog = &mut user_manager.user_address_catalog;
        assert!(table::contains(&mut user_catalog.user_address_to_user_id, user), ENOT_EXIST_USER);
        *table::borrow(&mut user_catalog.user_address_to_user_id, user)
    }

    public fun get_user_addresses(user_manager: &mut UserManagerInfo, dola_user_id: u64): vector<DolaAddress> {
        let user_catalog = &mut user_manager.user_address_catalog;
        assert!(table::contains(&mut user_catalog.user_id_to_addresses, dola_user_id), ENOT_EXIST_USER);
        *table::borrow(&mut user_catalog.user_id_to_addresses, dola_user_id)
    }

    public fun register_dola_user_id(_: &UserManagerCap, user_manager: &mut UserManagerInfo, user: DolaAddress) {
        let user_catalog = &mut user_manager.user_address_catalog;
        assert!(!table::contains(&mut user_catalog.user_address_to_user_id, user), EALREADY_EXIST_USER);
        let dola_user_id = table::length(&user_catalog.user_id_to_addresses);
        table::add(&mut user_catalog.user_address_to_user_id, user, dola_user_id);
        let user_addresses = vector::empty<DolaAddress>();
        vector::push_back(&mut user_addresses, user);
        table::add(&mut user_catalog.user_id_to_addresses, dola_user_id, user_addresses);
    }

    public fun binding_user_address(
        _: &UserManagerCap,
        user_manager: &mut UserManagerInfo,
        user: DolaAddress,
        bind_address: DolaAddress
    ) {
        let dola_user_id = get_dola_user_id(user_manager, user);
        let user_catalog = &mut user_manager.user_address_catalog;
        assert!(!table::contains(&mut user_catalog.user_address_to_user_id, bind_address), EALREADY_EXIST_USER);
        table::add(&mut user_catalog.user_address_to_user_id, bind_address, dola_user_id);
        let user_addresses = table::borrow_mut(&mut user_catalog.user_id_to_addresses, dola_user_id);
        assert!(vector::contains(user_addresses, &bind_address), ENOT_EXIST_USER);
        vector::push_back(user_addresses, bind_address);
    }

    public fun unbinding_user_address(
        _: &UserManagerCap,
        user_manager: &mut UserManagerInfo,
        unbind_address: DolaAddress
    ) {
        let unbind_user_id = get_dola_user_id(user_manager, unbind_address);
        let user_catelog = &mut user_manager.user_address_catalog;
        let user_addresses = table::borrow_mut(&mut user_catelog.user_id_to_addresses, unbind_user_id);
        let length = vector::length(user_addresses);
        assert!(length >= 2, ETOO_FEW_ADDRESSES);
        let i = 0;
        while (i < length) {
            let user_address = vector::borrow(user_addresses, i);
            if (user_address == &unbind_address) {
                vector::remove(user_addresses, i);
                break
            };
            i = i + 1;
        };
        table::remove(&mut user_catelog.user_address_to_user_id, unbind_address);
    }


    public fun encode_binding(user: DolaAddress, bind_address: DolaAddress): vector<u8> {
        let binding_payload = vector::empty<u8>();

        let user = encode_dola_address(user);
        serialize_u16(&mut binding_payload, (vector::length(&user) as u16));
        serialize_vector(&mut binding_payload, user);

        let bind_address = encode_dola_address(bind_address);
        serialize_u16(&mut binding_payload, (vector::length(&bind_address) as u16));
        serialize_vector(&mut binding_payload, bind_address);

        serialize_u8(&mut binding_payload, BINDING);
        binding_payload
    }

    public fun decode_binding(binding_payload: vector<u8>): (DolaAddress, DolaAddress, u8) {
        let length = vector::length(&binding_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let user_len = deserialize_u16(&vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user = decode_dola_address(vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = deserialize_u16(&vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = (bind_len as u64);
        let bind_address = decode_dola_address(vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&binding_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (user, bind_address, call_type)
    }

    public fun encode_unbinding(unbind_address: DolaAddress): vector<u8> {
        let unbinding_payload = vector::empty<u8>();
        let unbind_address = encode_dola_address(unbind_address);
        serialize_u16(&mut unbinding_payload, (vector::length(&unbind_address) as u16));
        serialize_vector(&mut unbinding_payload, unbind_address);

        serialize_u8(&mut unbinding_payload, UNBINDING);
        unbinding_payload
    }

    public fun decode_unbinding(unbinding_payload: vector<u8>): (DolaAddress, u8) {
        let length = vector::length(&unbinding_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let unbind_len = deserialize_u16(&vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        data_len = (unbind_len as u64);
        let unbind_address = decode_dola_address(vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&unbinding_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (unbind_address, call_type)
    }
}
