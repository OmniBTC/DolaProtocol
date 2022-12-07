/// Simply update the prices and get them for testing purposes only,
/// prices will be obtained from other oracles subsequently.
module oracle::oracle {
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    const ENONEXISTENT_ORACLE: u64 = 0;

    const EALREADY_EXIST_ORACLE: u64 = 1;

    struct OracleCap has key {
        id: UID
    }

    struct PriceOracle has key {
        id: UID,
        // todo: use sui timestamp
        timestamp: u64,
        // token name => price
        price_oracles: Table<vector<u8>, Price>
    }

    struct Price has store {
        value: u64,
        // 2 decimals should be 100,
        decimal: u8
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PriceOracle {
            id: object::new(ctx),
            timestamp: 0,
            price_oracles: table::new(ctx)
        });
        transfer::transfer(OracleCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }

    public entry fun register_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        timestamp: u64,
        token_name: vector<u8>,
        token_price: u64,
        price_decimal: u8
    ) {
        price_oracle.timestamp = timestamp;
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(!table::contains(price_oracles, token_name), EALREADY_EXIST_ORACLE);
        table::add(price_oracles, token_name, Price {
            value: token_price,
            decimal: price_decimal
        })
    }

    public entry fun update_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        token_name: vector<u8>,
        token_price: u64
    ) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, token_name), ENONEXISTENT_ORACLE);
        let price = table::borrow_mut(price_oracles, token_name);
        price.value = token_price;
    }

    public fun get_token_price(price_oracle: &mut PriceOracle, token_name: vector<u8>): (u64, u8) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, token_name), ENONEXISTENT_ORACLE);
        let price = table::borrow(price_oracles, token_name);
        (price.value, price.decimal)
    }

    public entry fun update_timestamp(_: &OracleCap, oracle: &mut PriceOracle, timestamp: u64) {
        oracle.timestamp = timestamp;
    }

    public fun get_timestamp(oracle: &mut PriceOracle): u64 {
        oracle.timestamp
    }
}
