module time_oracle::timestamp {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct Timestamp has key {
        id: UID,
        timestamp: u64
    }

    struct OracleCap has key, store {
        id: UID
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(OracleCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
        transfer::share_object(Timestamp {
            id: object::new(ctx),
            timestamp: 0
        })
    }

    public entry fun update_timestamp(_: &OracleCap, time: &mut Timestamp, timestamp: u64) {
        time.timestamp = timestamp;
    }

    public fun get_timestamp(time: &mut Timestamp): u64 {
        time.timestamp
    }
}
