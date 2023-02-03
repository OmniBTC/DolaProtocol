module governance::basic {
    use sui::object::{UID, ID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::object;
    use std::vector;

    friend governance::governance_v1;

    /// Governance rights struct, responsible for governing all modules of Dola protocol
    struct GovernanceCap {}

    /// Used to create and destroy `GovernanceCap`.
    /// `GovernanceManagerCap` is hosted for specific voting modules (v1, v2...) ,
    /// to help with possible future upgrades of the voting module itself.
    struct GovernanceManagerCap has key {
        id: UID
    }

    /// Record the existing `GovernanceManagerCap` object
    struct GovernanceBasic has key {
        id: UID,
        manager_ids: vector<ID>
    }


    fun init(ctx: &mut TxContext) {
        transfer::share_object(GovernanceBasic {
            id: object::new(ctx),
            manager_ids: vector::empty()
        });
    }

    public(friend) fun new(governance_basic: &mut GovernanceBasic, ctx: &mut TxContext): GovernanceManagerCap {
        let governance_manager_cap = GovernanceManagerCap {
            id: object::new(ctx)
        };
        vector::push_back(&mut governance_basic.manager_ids, object::id(&governance_manager_cap));
        governance_manager_cap
    }

    public fun create(_: &GovernanceManagerCap): GovernanceCap {
        GovernanceCap {}
    }

    public fun destroy(_: &GovernanceManagerCap, governance_cap: GovernanceCap) {
        let GovernanceCap {} = governance_cap;
    }

    public fun destroy_manager(governance_basic: &mut GovernanceBasic, governance_manager_cap: GovernanceManagerCap) {
        let manager_id = object::id(&governance_manager_cap);
        let (_, index ) = vector::index_of(&governance_basic.manager_ids, &manager_id);
        vector::remove(&mut governance_basic.manager_ids, index);
        let GovernanceManagerCap { id } = governance_manager_cap;
        object::delete(id);
    }
}
