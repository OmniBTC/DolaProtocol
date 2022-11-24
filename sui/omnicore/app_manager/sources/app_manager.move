module app_manager::app_manager {
    use serde::u16::{Self, U16};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct AppManagerCap has key, store {
        id: UID,
    }

    struct TotalAppInfo has key, store {
        id: UID,
        count: U16
    }

    struct AppCap has key, store {
        id: UID,
        app_id: U16
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(TotalAppInfo {
            id: object::new(ctx),
            count: u16::from_u64(0)
        });
        transfer::transfer(AppManagerCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }

    public fun app_id(app_id: &AppCap): U16 {
        app_id.app_id
    }

    public fun register_app(_: &AppManagerCap, total_app_info: &mut TotalAppInfo, ctx: &mut TxContext): AppCap {
        let count = u16::to_u64(total_app_info.count);
        let app_id = AppCap {
            id: object::new(ctx),
            app_id: u16::from_u64(count)
        };
        total_app_info.count = u16::from_u64(count + 1);
        app_id
    }

    public fun destroy_app_id(app_id: AppCap) {
        let AppCap { id, app_id: _ } = app_id;
        object::delete(id);
    }
}
