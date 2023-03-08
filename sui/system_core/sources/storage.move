module system_core::storage {
    use sui::object::UID;
    use app_manager::app_manager::{AppCap, TotalAppInfo};
    use user_manager::user_manager::UserManagerCap;
    use governance::genesis::GovernanceCap;
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::object;
    use user_manager::user_manager;
    use app_manager::app_manager;

    struct Storage has key {
        id: UID,
        /// Used in representative system app
        app_cap: AppCap,
        // Allow modification of user_manager storage through UserManagerCap
        user_manager_cap: UserManagerCap,
    }

    /// Used to remove app_cap and user_manager_cap from Storage
    struct StorageCap has store, drop {}

    public fun initialize_cap_with_governance(
        governance: &GovernanceCap,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    ) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            app_cap: app_manager::register_cap_with_governance(governance, total_app_info, ctx),
            user_manager_cap: user_manager::register_cap_with_governance(governance),
        })
    }

    public fun register_cap_with_governance(_: &GovernanceCap): StorageCap {
        StorageCap {}
    }

    /// Get app cap
    public fun get_app_cap(
        _: &StorageCap,
        storage: &Storage
    ): &AppCap {
        &storage.app_cap
    }

    /// Get user manager cap
    public fun get_user_manager_cap(
        _: &StorageCap,
        storage: &Storage
    ): &UserManagerCap {
        &storage.user_manager_cap
    }
}
