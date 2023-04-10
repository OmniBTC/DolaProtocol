// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module app_manager::app_manager {
    use std::vector;

    use governance::genesis::{GovernanceCap, GovernanceContracts};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::package;
    use sui::package::UpgradeCap;
    use governance::genesis;

    /// Errors
    const EINVALID_UPGRADE_CAP: u64 = 0;


    /// Record all App information
    struct TotalAppInfo has key, store {
        id: UID,
        app_caps: vector<ID>
    }

    /// Giving applications access to the bridge adapter through AppCap
    struct AppCap has key, store {
        id: UID,
        app_id: u16
    }

    /// Initializing caps of PoolManager and UserManager through governance
    public fun initialize_cap_with_governance(
        _: &GovernanceCap,
        gov_contracts: &mut GovernanceContracts,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let package_id = object::id_to_address(&package::upgrade_package(&upgrade_cap));
        assert!(package_id == @app_manager, EINVALID_UPGRADE_CAP);
        genesis::add_upgrade_cap(gov_contracts, upgrade_cap);
        transfer::share_object(TotalAppInfo {
            id: object::new(ctx),
            app_caps: vector::empty()
        });
    }

    /// Register app cap for application
    fun register_app(total_app_info: &mut TotalAppInfo, ctx: &mut TxContext): AppCap {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        let app_id = AppCap {
            id: uid,
            app_id: (vector::length(&total_app_info.app_caps) as u16)
        };

        vector::push_back(&mut total_app_info.app_caps, id);

        app_id
    }

    /// Register cap through governance
    public fun register_cap_with_governance(
        _: &GovernanceCap,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): AppCap {
        register_app(total_app_info, ctx)
    }

    /// Get app id by app cap
    public fun get_app_id(app_id: &AppCap): u16 {
        app_id.app_id
    }

    /// Destroy app cap
    public fun destroy_app_cap(app_id: AppCap) {
        let AppCap { id, app_id: _ } = app_id;
        object::delete(id);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        transfer::share_object(TotalAppInfo {
            id: object::new(ctx),
            app_caps: vector::empty()
        });
    }

    #[test_only]
    public fun register_app_for_testing(total_app_info: &mut TotalAppInfo, ctx: &mut TxContext): AppCap {
        register_app(total_app_info, ctx)
    }
}
