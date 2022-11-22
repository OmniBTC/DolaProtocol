module lending_portal::lending {
    use std::vector;

    use omnipool::pool::Pool;
    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64};
    use serde::u16::{Self, U16};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_pool::{send_deposit, PoolState, send_withdraw, send_deposit_and_withdraw};

    const APPID: u64 = 0;

    /// Call types for relayer call
    const SUPPLY: u64 = 0;

    const WITHDRAW: u64 = 1;

    const BORROW: u64 = 2;

    const REPAY: u64 = 3;

    const LIQUIDATE: u64 = 4;

    public fun app_id(): U16 {
        u16::from_u64(APPID)
    }

    public entry fun supply<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        ctx: &mut TxContext
    ) {
        let app_payload = encode_app_payload(coin::value(&deposit_coin));
        send_deposit(pool_state, wormhole_state, wormhole_message_fee, pool, deposit_coin, app_id(), app_payload, ctx);
    }

    public entry fun withdraw<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let app_payload = encode_app_payload(amount);
        send_withdraw(pool, pool_state, wormhole_state, wormhole_message_fee, app_id(), app_payload, ctx);
    }

    public entry fun borrow<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let app_payload = encode_app_payload(amount);
        send_withdraw(pool, pool_state, wormhole_state, wormhole_message_fee, app_id(), app_payload, ctx);
    }

    public entry fun repay<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        repay_coin: Coin<CoinType>,
        ctx: &mut TxContext
    ) {
        let app_payload = encode_app_payload(coin::value(&repay_coin));
        send_deposit(pool_state, wormhole_state, wormhole_message_fee, pool, repay_coin, app_id(), app_payload, ctx);
    }

    public entry fun liquidate<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        // liquidators repay debts to obtain collateral
        debt_coin: Coin<CoinType>,
        ctx: &mut TxContext
    ) {
        let app_payload = encode_app_payload(coin::value(&debt_coin));
        send_deposit_and_withdraw(
            pool_state,
            wormhole_state,
            wormhole_message_fee,
            pool,
            debt_coin,
            app_id(),
            app_payload,
            ctx
        );
    }

    public entry fun encode_app_payload(call_type: u8, amount: u64): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u8(&mut payload, call_type);
        serialize_u64(&mut payload, amount);
        payload
    }

    public entry fun decode_app_payload(app_payload: vector<u8>): (u8, u64) {
        let length = vector::length(&app_payload);
        let index = 0;
        let data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        (call_type, amount)
    }
}
