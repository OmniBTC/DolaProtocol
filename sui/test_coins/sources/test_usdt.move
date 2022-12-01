module test_coins::usdt {
    use sui::coin;
    use sui::tx_context::TxContext;

    use test_coins::lock::creator_lock;

    /// USDT for test
    struct USDT has drop {}

    fun init(witness: USDT, ctx: &mut TxContext) {
        let treasury_cap = coin::create_currency(
            witness,
            8,
            ctx
        );

        creator_lock(treasury_cap, ctx)
    }
}
