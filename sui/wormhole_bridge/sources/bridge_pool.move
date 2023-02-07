module wormhole_bridge::bridge_pool {
    use std::vector;

    use dola_types::types::{DolaAddress, create_dola_address, convert_address_to_dola};
    use governance::genesis::GovernanceCap;
    use omnipool::pool::{Self, Pool, PoolCap, deposit_and_withdraw};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, UID};
    use sui::object_table;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};
    use user_manager::user_manager::{encode_binding, encode_unbinding};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::state::State as WormholeState;
    use wormhole::wormhole;
    use wormhole_bridge::verify::Unit;

    const ENOT_ENOUGH_AMOUNT: u64 = 0;

    const EMUST_ZERO: u64 = 1;

    const U64_MAX: u64 = 18446744073709551615;

    struct PoolState has key, store {
        id: UID,
        pool_cap: PoolCap,
        sender: EmitterCapability,
        consumed_vaas: object_table::ObjectTable<vector<u8>, Unit>,
        registered_emitters: VecMap<u16, ExternalAddress>,
        // todo! Delete after wormhole running
        cache_vaas: Table<u64, vector<u8>>
    }

    struct VaaEvent has copy, drop {
        vaa: vector<u8>,
        nonce: u64
    }

    struct VaaReciveWithdrawEvent has copy, drop {
        pool_address: DolaAddress,
        user: DolaAddress,
        amount: u64
    }

    public fun initialize_wormhole_with_governance(
        governance: &GovernanceCap,
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    ) {
        transfer::share_object(
            PoolState {
                id: object::new(ctx),
                pool_cap: pool::register_cap(governance, ctx),
                sender: wormhole::register_emitter(wormhole_state, ctx),
                consumed_vaas: object_table::new(ctx),
                registered_emitters: vec_map::empty(),
                cache_vaas: table::new(ctx)
            }
        );
    }

    public fun register_remote_bridge(
        _: &GovernanceCap,
        pool_state: &mut PoolState,
        emitter_chain_id: u16,
        emitter_address: vector<u8>,
        _ctx: &mut TxContext
    ) {
        // todo! consider remote register
        vec_map::insert(
            &mut pool_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    public entry fun send_binding(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        dola_chain_id: u16,
        bind_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let bind_address = create_dola_address(dola_chain_id, bind_address);
        let user = tx_context::sender(ctx);
        let user = convert_address_to_dola(user);
        let msg = encode_binding(user, bind_address);
        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
    }

    public entry fun send_unbinding(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        dola_chain_id: u16,
        unbind_address: vector<u8>,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let user = convert_address_to_dola(user);
        let unbind_address = create_dola_address(dola_chain_id, unbind_address);
        let msg = encode_unbinding(user, unbind_address);
        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        wormhole::publish_message(&mut pool_state.sender, wormhole_state, 0, msg, wormhole_message_fee);
        let index = table::length(&pool_state.cache_vaas) + 1;
        table::add(&mut pool_state.cache_vaas, index, msg);
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
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ) {
        let msg = deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
            deposit_pool,
            deposit_coin,
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
        // let (_pool_address, user, amount, dola_pool_id) =
        //     pool::decode_receive_withdraw_payload(myvaa::get_payload(&vaa));
        let (pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        pool::inner_withdraw(&pool_state.pool_cap, pool, user, amount, pool_address, ctx);
        // myvaa::destroy(vaa);
    }

    public entry fun read_vaa(pool_state: &PoolState, index: u64) {
        if (index == 0) {
            index = table::length(&pool_state.cache_vaas);
        };
        event::emit(VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index),
            nonce: index
        })
    }

    public entry fun decode_receive_withdraw_payload(vaa: vector<u8>) {
        let (pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);

        event::emit(VaaReciveWithdrawEvent {
            pool_address,
            user,
            amount
        })
    }

    public fun merge_coin<CoinType>(
        coins: vector<Coin<CoinType>>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<CoinType> {
        let len = vector::length(&coins);
        if (len > 0) {
            vector::reverse(&mut coins);
            let base_coin = vector::pop_back(&mut coins);
            while (!vector::is_empty(&coins)) {
                coin::join(&mut base_coin, vector::pop_back(&mut coins));
            };
            vector::destroy_empty(coins);
            let sum_amount = coin::value(&base_coin);
            let split_amount = amount;
            if (amount == U64_MAX) {
                split_amount = sum_amount;
            };
            assert!(sum_amount >= split_amount, ENOT_ENOUGH_AMOUNT);
            if (coin::value(&base_coin) > split_amount) {
                let split_coin = coin::split(&mut base_coin, split_amount, ctx);
                transfer::transfer(base_coin, tx_context::sender(ctx));
                split_coin
            }else {
                base_coin
            }
        }else {
            vector::destroy_empty(coins);
            assert!(amount == 0, EMUST_ZERO);
            coin::zero<CoinType>(ctx)
        }
    }
}
