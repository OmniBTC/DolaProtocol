/// Simply update the prices and get them for testing purposes only,
/// prices will be obtained from other oracles subsequently.
module oracle::oracle {
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    const ENONEXISTENT_ORACLE: u64 = 0;

    struct OracleCap has key {
        id: UID
    }

    struct PriceOracle has key {
        id: UID,
        // token name => price
        price_oracles: Table<vector<u8>, Price>
    }

    struct Price has store {
        value: u64,
        // 2 decimals should be 100,
        decimal: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PriceOracle {
            id: object::new(ctx),
            price_oracles: table::new(ctx)
        });
        transfer::transfer(OracleCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }

    public entry fun update_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        token_name: vector<u8>,
        token_price: u64
    ) {
        let price_oracles = &mut price_oracle.price_oracles;
        if (!table::contains(price_oracles, token_name)) {
            table::add(price_oracles, token_name, Price { value: 0, decimal: 0 });
        };
        let price = table::borrow_mut(price_oracles, token_name);
        price.value = token_price;
    }

    public fun get_token_price(price_oracle: &mut PriceOracle, token_name: vector<u8>): (u64, u64) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, token_name), ENONEXISTENT_ORACLE);
        let price = table::borrow(price_oracles, token_name);
        (price.value, price.decimal)
    }
}
