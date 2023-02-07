module app_manager::app_manager {
    use governance::genesis::GovernanceCap;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

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

    public fun register_cap_with_governance(
        _: &GovernanceCap,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ): AppCap {
        register_app(total_app_info, ctx)
    }

    public fun app_id(app_id: &AppCap): u16 {
        app_id.app_id
    }

    fun register_app(total_app_info: &mut TotalAppInfo, ctx: &mut TxContext): AppCap {
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

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun register_app_for_testing(total_app_info: &mut TotalAppInfo, ctx: &mut TxContext): AppCap {
        register_app(total_app_info, ctx)
    }
}
