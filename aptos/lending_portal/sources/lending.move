module lending_portal::lending {
    use std::vector;

    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64, serialize_u16, serialize_vector, deserialize_u16};
    use wormhole_bridge::bridge_pool::{send_deposit, send_withdraw, send_deposit_and_withdraw};
    use aptos_framework::coin::Coin;
    use std::bcs;
    use std::signer;
    use wormhole::state;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use serde::u16::{Self, U16};
    use omnipool::pool::normal_amount;

    const EINVALID_LENGTH: u64 = 0;

    const APPID: u64 = 0;

    /// Call types for relayer call
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
    ) {
        let user = bcs::to_bytes(&signer::address_of(sender));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let app_payload = encode_app_payload(
            SUPPLY,
            normal_amount<CoinType>(deposit_coin),
            user,
            u16::from_u64(0)
        );
        let deposit_coin = coin::withdraw<CoinType>(sender, deposit_coin);

        send_deposit(sender, wormhole_message_fee, deposit_coin, u16::from_u64(APPID), app_payload);
    }

    public entry fun withdraw<CoinType>(
        sender: &signer,
        dst_chain: u64,
        amount: u64,
    ) {
        let user = bcs::to_bytes(&signer::address_of(sender));
        let app_payload = encode_app_payload(
            WITHDRAW,
            normal_amount<CoinType>(amount),
            user,
            u16::from_u64(dst_chain));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        send_withdraw<CoinType>(sender, wormhole_message_fee, u16::from_u64(APPID), app_payload);
    }

    public entry fun borrow<CoinType>(
        sender: &signer,
        dst_chain: u64,
        amount: u64,
    ) {
        let user = bcs::to_bytes(&signer::address_of(sender));
        let app_payload = encode_app_payload(
            BORROW,
            normal_amount<CoinType>(amount),
            user,
            u16::from_u64(dst_chain));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_withdraw<CoinType>(sender, wormhole_message_fee, u16::from_u64(APPID), app_payload);
    }

    public entry fun repay<CoinType>(
        sender: &signer,
        repay_coin: u64,
    ) {
        let user = bcs::to_bytes(&signer::address_of(sender));

        let app_payload = encode_app_payload(
            REPAY,
            normal_amount<CoinType>(repay_coin),
            user,
            u16::from_u64(0));
        let repay_coin = coin::withdraw<CoinType>(sender, repay_coin);

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_deposit(sender, wormhole_message_fee, repay_coin, u16::from_u64(APPID), app_payload);
    }

    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        sender: &signer,
        dst_chain: u64,
        wormhole_message_fee: Coin<AptosCoin>,
        debt_coin: u64,
        // punished person
        punished: address,
    ) {
        let app_payload = encode_app_payload(
            LIQUIDATE,
            normal_amount<DebtCoinType>(debt_coin),
            bcs::to_bytes(&punished),
            u16::from_u64(dst_chain));
        let debt_coin = coin::withdraw<DebtCoinType>(sender, debt_coin);

        send_deposit_and_withdraw<DebtCoinType, CollateralCoinType>(
            sender,
            wormhole_message_fee,
            debt_coin,
            punished,
            u16::from_u64(APPID),
            app_payload,
        );
    }

    public fun encode_app_payload(call_type: u8, amount: u64, user: vector<u8>, dst_chain: U16): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u16(&mut payload, dst_chain);
        serialize_u64(&mut payload, amount);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&user)));
        serialize_vector(&mut payload, user);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (U16, u8, u64, vector<u8>) {
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

        data_len = u16::to_u64(user_length);
        let user = vector_slice(&app_payload, index, index + data_len);
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (chain_id, call_type, amount, user)
    }
}
