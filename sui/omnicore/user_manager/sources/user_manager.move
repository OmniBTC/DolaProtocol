module user_manager::user_manager {
    use std::vector;

    use dola_types::types::DolaAddress;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const ENOT_EXIST_USER: u64 = 0;

    const EALREADY_EXIST_USER: u64 = 1;

    const EDUPLICATED_BINDING: u64 = 2;

    struct UserManagerInfo has key, store {
        id: UID,
        user_address_catalog: UserAddressCatalog
    }

    struct UserAddressCatalog has store {
        user_address_to_user_id: Table<DolaAddress, u64>,
        user_id_to_addresses: Table<u64, vector<DolaAddress>>
    }

    struct UserManagerCap has key, store {
        id: UID
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(UserManagerInfo {
            id: object::new(ctx),
            user_address_catalog: UserAddressCatalog {
                user_address_to_user_id: table::new(ctx),
                user_id_to_addresses: table::new(ctx)
            }
        })
    }

    public fun register_cap(ctx: &mut TxContext): UserManagerCap {
        // todo! consider into govern
        UserManagerCap {
            id: object::new(ctx)
        }
    }

    public fun delete_cap(user_manager_cap: UserManagerCap) {
        let UserManagerCap { id } = user_manager_cap;
        object::delete(id);
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
        assert!(table::contains(&mut user_catalog.user_address_to_user_id, user), ENOT_EXIST_USER);
        assert!(!table::contains(&mut user_catalog.user_address_to_user_id, bind_address), EALREADY_EXIST_USER);
        table::add(&mut user_catalog.user_address_to_user_id, bind_address, dola_user_id);
        let user_addresses = table::borrow_mut(&mut user_catalog.user_id_to_addresses, dola_user_id);
        assert!(vector::contains(user_addresses, &bind_address), ENOT_EXIST_USER);
        vector::push_back(user_addresses, bind_address);
    }
}
