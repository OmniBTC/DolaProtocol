// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

module dola_protocol::system_core_storage {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::app_manager::{Self, AppCap, TotalAppInfo};
    use dola_protocol::genesis::GovernanceCap;

    friend dola_protocol::system_core_wormhole_adapter;

    struct Storage has key {
        id: UID,
        /// Used in representative system app
        app_cap: AppCap,
    }

    /// === Initial Functions ===

    public fun initialize_cap_with_governance(
        governance: &GovernanceCap,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            app_cap: app_manager::register_cap_with_governance(governance, total_app_info, ctx),
        })
    }

    /// === Friend Functions ===

    /// Get app cap
    public(friend) fun get_app_cap(
        storage: &Storage
    ): &AppCap {
        &storage.app_cap
    }
}
