module wormhole_bridge::bridge {
    use omnipool::pool;
    use omnipool::pool::Pool;
    use sui::coin::Coin;
    use sui::tx_context::TxContext;
    use wormhole::wormhole;
    use wormhole::emitter::EmitterCapability;
    use sui::transfer;
    use wormhole::state::State;
    use sui::tx_context;
    use sui::sui::SUI;

    const EMUST_DEPLOYER: u64 = 0;

    struct WormholeBridgeInfo has key {
        sender: EmitterCapability
    }

    public entry fun initialize_wormhole(state: &mut State, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == @wormhole_bridge, EMUST_DEPLOYER);
        let sender = wormhole::register_emitter(state, ctx);
        transfer::share_object(WormholeBridgeInfo { sender });
    }

    public entry fun send<CoinType>(
        wormhole_bridge_info: &mut WormholeBridgeInfo,
        wormhole_state: &mut State,
        wormhole_message_fee: Coin<SUI>,
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
        wormhole::publish_message(&mut wormhole_bridge_info.sender, wormhole_state, 0, msg, wormhole_message_fee);
    }
}
