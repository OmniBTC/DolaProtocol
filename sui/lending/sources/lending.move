module lending_portal::lending {
    use std::vector;

    use omnipool::pool::Pool;
    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64, serialize_u16, serialize_vector, deserialize_u16};
    use serde::u16::{Self, U16};
    use sui::bcs::to_bytes;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_pool::{send_deposit, PoolState, send_withdraw, send_deposit_and_withdraw};

    const APPID: u64 = 0;

    /// Call types for relayer call
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

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
        let user = to_bytes(&tx_context::sender(ctx));
        let app_payload = encode_app_payload(SUPPLY, coin::value(&deposit_coin), user);
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
        let user = to_bytes(&tx_context::sender(ctx));
        let app_payload = encode_app_payload(WITHDRAW, amount, user);
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
        let user = to_bytes(&tx_context::sender(ctx));
        let app_payload = encode_app_payload(BORROW, amount, user);
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
        let user = to_bytes(&tx_context::sender(ctx));
        let app_payload = encode_app_payload(REPAY, coin::value(&repay_coin), user);
        send_deposit(pool_state, wormhole_state, wormhole_message_fee, pool, repay_coin, app_id(), app_payload, ctx);
    }

    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        // punished person
        punished: vector<u8>,
        collateral_pool: &mut Pool<CollateralCoinType>,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coin: Coin<DebtCoinType>,
        ctx: &mut TxContext
    ) {
        let app_payload = encode_app_payload(LIQUIDATE, coin::value(&debt_coin), punished);
        send_deposit_and_withdraw(
            pool_state,
            wormhole_state,
            wormhole_message_fee,
            collateral_pool,
            debt_pool,
            debt_coin,
            app_id(),
            app_payload,
            ctx
        );
    }

    public entry fun encode_app_payload(call_type: u8, amount: u64, user: vector<u8>): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u8(&mut payload, call_type);
        serialize_u64(&mut payload, amount);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&user)));
        serialize_vector(&mut payload, user);
        payload
    }

    public entry fun decode_app_payload(app_payload: vector<u8>): (u8, u64, vector<u8>) {
        let index = 0;
        let data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(user_length);
        let user = vector_slice(&app_payload, index, index + data_len);
        index = index + data_len;

        (call_type, amount, user)
    }
}
