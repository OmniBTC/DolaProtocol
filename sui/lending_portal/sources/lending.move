module lending_portal::lending {
    use std::vector;

    use omnipool::pool::{Pool, normal_amount, DolaAddress, convert_address_to_dola, encode_dola_address, decode_dola_address, convert_external_address_to_dola};
    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64, serialize_u16, serialize_vector, deserialize_u16};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_pool::{send_deposit, PoolState, send_withdraw, send_deposit_and_withdraw};
    use sui::transfer;

    const EINVALID_LENGTH: u64 = 0;

    const ENOT_ENOUGH_AMOUNT: u64 = 1;

    const EMUST_ZERO: u64 = 2;

    const APPID: u16 = 0;

    /// Call types for relayer call
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    const U64_MAX: u64 = 18446744073709551615;

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

    public entry fun supply<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        pool: &mut Pool<CoinType>,
        deposit_coins: vector<Coin<CoinType>>,
        deposit_amount: u64,
        ctx: &mut TxContext
    ) {
        let user = convert_address_to_dola(tx_context::sender(ctx));
        let deposit_coin = merge_coin<CoinType>(deposit_coins, deposit_amount, ctx);
        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        let app_payload = encode_app_payload(SUPPLY, normal_amount(pool,coin::value(&deposit_coin)), user, 0);
        send_deposit(pool_state, wormhole_state, wormhole_message_fee, pool, deposit_coin, APPID, app_payload, ctx);
    }

    public entry fun withdraw<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let user = convert_address_to_dola(tx_context::sender(ctx));
        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        let app_payload = encode_app_payload(WITHDRAW, normal_amount(pool,amount), user, dst_chain);
        send_withdraw(pool, pool_state, wormhole_state, wormhole_message_fee, APPID, app_payload, ctx);
    }

    public entry fun borrow<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let user = convert_address_to_dola(tx_context::sender(ctx));
        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        let app_payload = encode_app_payload(BORROW, normal_amount(pool,amount), user, dst_chain);
        send_withdraw(pool, pool_state, wormhole_state, wormhole_message_fee, APPID, app_payload, ctx);
    }

    public entry fun repay<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        ctx: &mut TxContext
    ) {
        let user = convert_address_to_dola(tx_context::sender(ctx));
        let repay_coin = merge_coin<CoinType>(repay_coins, repay_amount, ctx);
        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        let app_payload = encode_app_payload(REPAY, normal_amount(pool,coin::value(&repay_coin)), user, 0);
        send_deposit(pool_state, wormhole_state, wormhole_message_fee, pool, repay_coin, APPID, app_payload, ctx);
    }

    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coins: vector<Coin<DebtCoinType>>,
        debt_amount: u64,
        // punished person
        punished: vector<u8>,
        ctx: &mut TxContext
    ) {
        let debt_coin = merge_coin<DebtCoinType>(debt_coins, debt_amount, ctx);

        let wormhole_message_fee = merge_coin<SUI>(wormhole_message_coins, wormhole_message_amount, ctx);
        let app_payload = encode_app_payload(LIQUIDATE, normal_amount(debt_pool,coin::value(&debt_coin)),
            convert_external_address_to_dola(vector_slice(&punished,0, vector::length(&punished))), dst_chain);
        send_deposit_and_withdraw<DebtCoinType, CollateralCoinType>(
            pool_state,
            wormhole_state,
            wormhole_message_fee,
            debt_pool,
            debt_coin,
            convert_external_address_to_dola(punished),
            APPID,
            app_payload,
            ctx
        );
    }

    public fun encode_app_payload(call_type: u8, amount: u64, user: DolaAddress, dst_chain: u16): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u16(&mut payload, dst_chain);
        serialize_u64(&mut payload, amount);
        let user = encode_dola_address(user);
        serialize_u16(&mut payload, (vector::length(&user) as u16));
        serialize_vector(&mut payload, user);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (u8, u64, DolaAddress, u16) {
        let index = 0;
        let data_len;

        data_len = 2;
        let chain_id = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_length as u64);
        let user = decode_dola_address(vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (call_type, amount, user, chain_id)
    }

    #[test]
    fun test_encode_decode() {
        let user = @0x11;
        let payload = encode_app_payload(WITHDRAW, 100000000, convert_address_to_dola(user), 1);
        let ( call_type, amount, user_addr, chain_id) = decode_app_payload(payload);
        assert!(chain_id == 1, 0);
        assert!(call_type == WITHDRAW, 0);
        assert!(amount == 100000000, 0);
        assert!(user_addr == convert_address_to_dola(user), 0);
    }
}
