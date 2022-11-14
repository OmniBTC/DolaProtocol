module wormhole_bridge::bridge {
    use omnipool::pool;
    use omnipool::pool::Pool;
    use sui::coin::Coin;
    use sui::tx_context::TxContext;


    public entry fun send<CoinType>(
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = pool::deposit_to<CoinType>(
            pool,
            deposit_coin,
            app_payload,
            ctx
        );

    }
}
