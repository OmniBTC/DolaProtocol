module wormhole_bridge::bridge {
    use omnipool::pool;
    use omnipool::pool::Pool;
    use sui::coin::Coin;
    use sui::tx_context::TxContext;
    use wormhole::wormhole;


    public entry fun send<CoinType>(
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let _msg = pool::deposit_to<CoinType>(
            pool,
            deposit_coin,
            app_payload,
            ctx
        );
        // wormhole::publish_message()
    }
}
