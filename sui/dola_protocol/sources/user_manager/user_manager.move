// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::user_manager {
    use std::vector;

    use sui::event;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::dola_address::{Self, DolaAddress};
    use dola_protocol::genesis::GovernanceCap;

    #[test_only]
    use dola_protocol::genesis;
    #[test_only]
    use sui::test_scenario;

    friend dola_protocol::system_core_wormhole_adapter;
    friend dola_protocol::lending_portal;
    friend dola_protocol::system_portal;
    friend dola_protocol::wormhole_adapter_core;

    /// Errors
    const EALREADY_USER: u64 = 0;

    const ENOT_USER: u64 = 1;

    const ETOO_FEW_ADDRESS: u64 = 2;

    const EALREADY_GROUP: u64 = 3;

    const ENOT_GROUP: u64 = 4;

    const EINVALID_UNBINDING: u64 = 5;

    /// Manage user addresses of different chains, bound with user id.
    /// Also group the dola chain ids, such as evm chains into the same group,
    /// to avoid duplicate bindings between evm chains.
    /// Note that the association of group ids requires caution.
    struct UserManagerInfo has key, store {
        id: UID,
        // user catalogs
        user_address_catalog: UserAddressCatalog,
        // dola_chain_id => group id
        chain_id_to_group: Table<u16, u16>
    }

    struct UserAddressCatalog has store {
        // user address => dola_user_id
        user_address_to_user_id: Table<DolaAddress, u64>,
        // dola_user_id => user addresses
        user_id_to_addresses: Table<u64, vector<DolaAddress>>
    }

    /// Events

    /// Bind dola_user_address to dola_user_id
    struct BindUser has copy, drop {
        dola_user_address: DolaAddress,
        dola_user_id: u64
    }

    /// Unbind dola_user_address to dola_user_id
    struct UnbindUser has copy, drop {
        dola_user_address: DolaAddress,
        dola_user_id: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(UserManagerInfo {
            id: object::new(ctx),
            user_address_catalog: UserAddressCatalog {
                user_address_to_user_id: table::new(ctx),
                user_id_to_addresses: table::new(ctx)
            },
            chain_id_to_group: table::new(ctx)
        })
    }

    /// === Governance Functions ===

    /// Register the chain ids that need to be grouped
    public fun register_dola_chain_id(
        _: &GovernanceCap,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        group_id: u16
    ) {
        let chain_id_to_group = &mut user_manager_info.chain_id_to_group;
        assert!(!table::contains(chain_id_to_group, dola_chain_id), EALREADY_GROUP);
        table::add(chain_id_to_group, dola_chain_id, group_id);
    }

    /// Unregister the chain ids that need to be grouped
    public fun unregister_dola_chain_id(
        _: &GovernanceCap,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16
    ) {
        let chain_id_to_group = &mut user_manager_info.chain_id_to_group;
        assert!(table::contains(chain_id_to_group, dola_chain_id), ENOT_GROUP);
        table::remove(chain_id_to_group, dola_chain_id);
    }

    /// === View Functions ===

    /// Get dola_user_id from DolaAddress
    public fun get_dola_user_id(user_manager_info: &UserManagerInfo, user_address: DolaAddress): u64 {
        let user_address = process_group_id(user_manager_info, user_address);
        let user_catalog = &user_manager_info.user_address_catalog;
        assert!(table::contains(&user_catalog.user_address_to_user_id, user_address), ENOT_USER);
        *table::borrow(&user_catalog.user_address_to_user_id, user_address)
    }

    /// Get all DolaAddressd from dola_user_id
    public fun get_user_addresses(user_manager_info: &UserManagerInfo, dola_user_id: u64): vector<DolaAddress> {
        let user_catalog = &user_manager_info.user_address_catalog;
        assert!(table::contains(&user_catalog.user_id_to_addresses, dola_user_id), ENOT_USER);
        *table::borrow(&user_catalog.user_id_to_addresses, dola_user_id)
    }

    /// === Helper Functions ===

    /// Convert DolaAddress to a new DolaAddress based on group_id
    public fun process_group_id(user_manager_info: &UserManagerInfo, user_address: DolaAddress): DolaAddress {
        let dola_chain_id = dola_address::get_dola_chain_id(&user_address);
        let chain_id_to_group = &user_manager_info.chain_id_to_group;
        if (table::contains(chain_id_to_group, dola_chain_id)) {
            dola_address::update_dola_chain_id(user_address, *table::borrow(chain_id_to_group, dola_chain_id))
        }else {
            user_address
        }
    }

    /// Determine if DolaAddress is already bound
    public fun is_dola_user(user_manager_info: &UserManagerInfo, user_address: DolaAddress): bool {
        let user_address = process_group_id(user_manager_info, user_address);
        let user_catalog = &user_manager_info.user_address_catalog;
        table::contains(&user_catalog.user_address_to_user_id, user_address)
    }

    /// === Friend Functions ===

    /// Register new DolaAddress
    public(friend) fun register_dola_user_id(
        user_manager_info: &mut UserManagerInfo,
        user_address: DolaAddress
    ) {
        let user_address = process_group_id(user_manager_info, user_address);
        let user_catalog = &mut user_manager_info.user_address_catalog;
        assert!(!table::contains(&mut user_catalog.user_address_to_user_id, user_address), EALREADY_USER);

        let dola_user_id = table::length(&user_catalog.user_id_to_addresses) + 1;
        let user_addresses = vector::empty<DolaAddress>();

        // Add dola address
        table::add(&mut user_catalog.user_address_to_user_id, user_address, dola_user_id);
        vector::push_back(&mut user_addresses, user_address);
        table::add(&mut user_catalog.user_id_to_addresses, dola_user_id, user_addresses);

        event::emit(BindUser {
            dola_user_address: user_address,
            dola_user_id
        });
    }

    /// Bind a DolaAddress to an existing DolaAddress
    public(friend) fun bind_user_address(
        user_manager_info: &mut UserManagerInfo,
        user_address: DolaAddress,
        binded_address: DolaAddress
    ) {
        let dola_user_id = get_dola_user_id(user_manager_info, user_address);

        let binded_address = process_group_id(user_manager_info, binded_address);
        let user_catalog = &mut user_manager_info.user_address_catalog;
        assert!(!table::contains(&mut user_catalog.user_address_to_user_id, binded_address), EALREADY_USER);
        let user_addresses = table::borrow_mut(&mut user_catalog.user_id_to_addresses, dola_user_id);

        // Add dola address
        table::add(&mut user_catalog.user_address_to_user_id, binded_address, dola_user_id);
        vector::push_back(user_addresses, binded_address);

        event::emit(BindUser {
            dola_user_address: binded_address,
            dola_user_id
        });
    }

    /// Unbind a DolaAddress to an existing DolaAddress
    public(friend) fun unbind_user_address(
        user_manager_info: &mut UserManagerInfo,
        user_address: DolaAddress,
        unbinded_address: DolaAddress
    ) {
        let dola_user_id = get_dola_user_id(user_manager_info, user_address);
        let unbind_user_id = get_dola_user_id(user_manager_info, unbinded_address);
        assert!(dola_user_id == unbind_user_id, EINVALID_UNBINDING);
        let unbinded_address = process_group_id(user_manager_info, unbinded_address);

        let user_catelog = &mut user_manager_info.user_address_catalog;
        let user_addresses = table::borrow_mut(&mut user_catelog.user_id_to_addresses, unbind_user_id);
        assert!(vector::length(user_addresses) >= 2, ETOO_FEW_ADDRESS);
        let (_, index) = vector::index_of(user_addresses, &unbinded_address);

        // Remove dola address
        table::remove(&mut user_catelog.user_address_to_user_id, unbinded_address);
        vector::remove(user_addresses, index);

        event::emit(UnbindUser {
            dola_user_address: unbinded_address,
            dola_user_id
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        transfer::share_object(UserManagerInfo {
            id: object::new(ctx),
            user_address_catalog: UserAddressCatalog {
                user_address_to_user_id: table::new(ctx),
                user_id_to_addresses: table::new(ctx)
            },
            chain_id_to_group: table::new(ctx)
        })
    }

    #[test]
    public fun test_register_chain_id() {
        let manager = @0x22;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_testing(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, manager);
        {
            let governance_cap = genesis::register_governance_cap_for_testing();
            let user_manager_info = test_scenario::take_shared<UserManagerInfo>(scenario);
            register_dola_chain_id(&governance_cap, &mut user_manager_info, 5, 2);
            assert!(*table::borrow(&user_manager_info.chain_id_to_group, 5) == 2, 0);
            genesis::destroy(governance_cap);

            test_scenario::return_shared(user_manager_info);
        };

        test_scenario::next_tx(scenario, manager);
        {
            let governance_cap = genesis::register_governance_cap_for_testing();
            let user_manager_info = test_scenario::take_shared<UserManagerInfo>(scenario);
            unregister_dola_chain_id(&governance_cap, &mut user_manager_info, 5);
            assert!(!table::contains(&user_manager_info.chain_id_to_group, 5), 0);
            genesis::destroy(governance_cap);

            test_scenario::return_shared(user_manager_info);
        };

        test_scenario::end(scenario_val);
    }


    #[test]
    public fun test_register_and_bind_address() {
        let manager = @0x22;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            init_for_testing(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, manager);
        {
            let governance_cap = genesis::register_governance_cap_for_testing();
            let user_manager_info = test_scenario::take_shared<UserManagerInfo>(scenario);
            register_dola_chain_id(&governance_cap, &mut user_manager_info, 2, 2);
            register_dola_chain_id(&governance_cap, &mut user_manager_info, 5, 2);
            assert!(*table::borrow(&user_manager_info.chain_id_to_group, 2) == 2, 0);
            assert!(*table::borrow(&user_manager_info.chain_id_to_group, 5) == 2, 0);
            genesis::destroy(governance_cap);

            test_scenario::return_shared(user_manager_info);
        };

        test_scenario::next_tx(scenario, manager);
        {
            let governance_cap = genesis::register_governance_cap_for_testing();
            let user_manager_info = test_scenario::take_shared<UserManagerInfo>(scenario);

            let user1 = dola_address::convert_address_to_dola(@11);
            let user2 = dola_address::update_dola_chain_id(user1, 2);
            let user3 = dola_address::update_dola_chain_id(user1, 3);
            let user4 = dola_address::update_dola_chain_id(user1, 5);
            register_dola_user_id(&mut user_manager_info, user1);
            assert!(get_dola_user_id(&user_manager_info, user1) == 1, 0);
            assert!(vector::contains(&get_user_addresses(&user_manager_info, 1), &user1), 0);
            register_dola_user_id(&mut user_manager_info, user4);
            assert!(get_dola_user_id(&user_manager_info, user2) == 2, 0);
            bind_user_address(&mut user_manager_info, user1, user3);
            assert!(get_dola_user_id(&user_manager_info, user3) == 1, 0);
            unbind_user_address(&mut user_manager_info, user3, user1);
            assert!(!vector::contains(&get_user_addresses(&user_manager_info, 1), &user1), 0);
            assert!(vector::contains(&get_user_addresses(&user_manager_info, 1), &user3), 0);

            genesis::destroy(governance_cap);

            test_scenario::return_shared(user_manager_info);
        };

        test_scenario::end(scenario_val);
    }
}
