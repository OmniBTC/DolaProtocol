module wormhole_bridge::bridge_pool {
    use omnipool::pool::{Self, Pool, PoolCap, deposit_and_withdraw};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::state::State as WormholeState;
    use wormhole::wormhole;
    use wormhole_bridge::verify::Unit;
    use sui::table::Table;
    use sui::table;
    use sui::event;

    const EMUST_DEPLOYER: u64 = 0;

    struct PoolState has key, store {
        id: UID,
        pool_cap: PoolCap,
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<u16, ExternalAddress>,
        cache_vaas: Table<u64, vector<u8>>
    }

    struct VaaEvent has copy, drop {
        vaa: vector<u8>
    }

    public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext) {
        transfer::share_object(
            PoolState {
                id: object::new(ctx),
                pool_cap: pool::register_cap(ctx),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty(),
                cache_vaas: table::new(ctx)
            }
        );
    }

    public entry fun register_remote_bridge(
        pool_state: &mut PoolState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        // todo! change into govern permission

        // todo! consider remote register
        vec_map::insert(
            &mut pool_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    public fun send_deposit<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = pool::deposit_to<CoinType>(
            pool,
            deposit_coin,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public fun send_withdraw<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = pool::withdraw_to<CoinType>(
            pool,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public fun send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        deposit_pool: &mut Pool<DepositCoinType>,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_pool: &mut Pool<WithdrawCoinType>,
        withdraw_user: address,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
            deposit_pool,
            deposit_coin,
            withdraw_pool,
            withdraw_user,
            app_id,
            app_payload,
            ctx
        );
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public entry fun receive_withdraw<CoinType>(
        _wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    ) {
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (_pool_address, user, amount, token_name) =
        //     pool::decode_receive_withdraw_payload(myvaa::get_payload(&vaa));
        let (_pool_address, user, amount, token_name) =
            pool::decode_receive_withdraw_payload(vaa);
        pool::inner_withdraw(&pool_state.pool_cap, pool, user, amount, token_name, ctx);
        // myvaa::destroy(vaa);
    }

    public entry fun read_vaa(pool_state: &PoolState, index: u64) {
        if (index == 0) {
            index = table::length(&pool_state.cache_vaas);
        };
        event::emit(VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index)
        })
    }
}
