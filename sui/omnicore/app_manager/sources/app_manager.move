module app_manager::app_manager {
    use std::hash;

    use governance::governance::{Self, GovernanceExternalCap};
    use sui::bcs;
    use sui::object::{Self, UID, uid_to_address};
    use sui::transfer;
    use sui::tx_context::TxContext;

    struct AppManagerCap has store, drop {
        total_app_info: address,
        count: u16
    }

    struct TotalAppInfo has key, store {
        id: UID,
        count: u16
    }

    struct AppCap has key, store {
        id: UID,
        app_id: u16
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(TotalAppInfo {
            id: object::new(ctx),
            count: 0
        })
    }

    public entry fun register_admin_cap(total_app_info: &mut TotalAppInfo, govern: &mut GovernanceExternalCap) {
        let admin = AppManagerCap { total_app_info: uid_to_address(&total_app_info.id), count: 0 };
        governance::add_external_cap(govern, hash::sha3_256(bcs::to_bytes(&admin)), admin);
    }

    public fun register_cap_with_admin(
        admin: &mut AppManagerCap,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): AppCap {
        admin.count = admin.count + 1;
        register_app(admin, total_app_info, ctx)
    }

    public fun app_id(app_id: &AppCap): u16 {
        app_id.app_id
    }

    fun register_app(_: &AppManagerCap, total_app_info: &mut TotalAppInfo, ctx: &mut TxContext): AppCap {
        let count = total_app_info.count;
        let app_id = AppCap {
            id: object::new(ctx),
            app_id: count
        };
        total_app_info.count = count + 1;
        app_id
    }

    public fun destroy_app_id(app_id: AppCap) {
        let AppCap { id, app_id: _ } = app_id;
        object::delete(id);
    }
}
