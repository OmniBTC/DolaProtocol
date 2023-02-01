module lending_portal::lending {
    use std::signer;
    use std::vector;

    use aptos_framework::account::new_event_handle;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event::{Self, EventHandle};

    use dola_types::types::{create_dola_address, decode_dola_address, DolaAddress, convert_address_to_dola, encode_dola_address};
    use omnipool::pool::normal_amount;
    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64, serialize_u16, serialize_vector, deserialize_u16};
    use serde::u16;
    use wormhole::state;
    use wormhole_bridge::bridge_pool::{send_deposit, send_withdraw, send_deposit_and_withdraw, send_withdraw_remote};

    const EINVALID_LENGTH: u64 = 0;

    const EINVALID_ACCOUNT: u64 = 1;

    const E_RESOURCE: u64 = 2;

    const APPID: u64 = 0;

    /// Call types for relayer call
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    struct LendingEventHandle has key {
        lending_started_handle: EventHandle<LendingStartedEvent>
    }

    struct LendingStartedEvent has store, drop {
        txid: vector<u8>
    }

    public entry fun initialize(account: &signer) {
        assert!(signer::address_of(account) == @lending_portal, EINVALID_ACCOUNT);
        move_to(account, LendingEventHandle {
            lending_started_handle: new_event_handle<LendingStartedEvent>(account)
        })
    }

    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
        txid: vector<u8>
    ) acquires LendingEventHandle {
        let user = convert_address_to_dola(signer::address_of(sender));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let app_payload = encode_app_payload(
            txid,
            SUPPLY,
            normal_amount<CoinType>(deposit_coin),
            user,
            0
        );
        let deposit_coin = coin::withdraw<CoinType>(sender, deposit_coin);

        send_deposit(sender, wormhole_message_fee, deposit_coin, u16::from_u64(APPID), app_payload);
        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public entry fun withdraw_local<CoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        amount: u64,
        txid: vector<u8>,
    ) acquires LendingEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver);

        let app_payload = encode_app_payload(
            txid,
            WITHDRAW,
            normal_amount<CoinType>(amount),
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        send_withdraw<CoinType>(sender, wormhole_message_fee, u16::from_u64(APPID), app_payload);

        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public entry fun withdraw_remote(
        sender: &signer,
        receiver: vector<u8>,
        pool: vector<u8>,
        dst_chain: u64,
        amount: u64,
        txid: vector<u8>,
    ) acquires LendingEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver);

        let app_payload = encode_app_payload(
            txid,
            WITHDRAW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        send_withdraw_remote(
            sender,
            wormhole_message_fee,
            pool,
            u16::from_u64(dst_chain),
            u16::from_u64(APPID),
            app_payload
        );
        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public entry fun borrow_local<CoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        amount: u64,
        txid: vector<u8>,
    ) acquires LendingEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver);

        let app_payload = encode_app_payload(
            txid,
            BORROW,
            normal_amount<CoinType>(amount),
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_withdraw<CoinType>(sender, wormhole_message_fee, u16::from_u64(APPID), app_payload);
        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public entry fun borrow_remote(
        sender: &signer,
        receiver: vector<u8>,
        pool: vector<u8>,
        dst_chain: u64,
        amount: u64,
        txid: vector<u8>,
    ) acquires LendingEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver);

        let app_payload = encode_app_payload(
            txid,
            BORROW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        send_withdraw_remote(
            sender,
            wormhole_message_fee,
            pool,
            u16::from_u64(dst_chain),
            u16::from_u64(APPID),
            app_payload
        );
        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public entry fun repay<CoinType>(
        sender: &signer,
        repay_coin: u64,
        txid: vector<u8>,
    ) acquires LendingEventHandle {
        let user_addr = convert_address_to_dola(signer::address_of(sender));

        let app_payload = encode_app_payload(
            txid,
            REPAY,
            normal_amount<CoinType>(repay_coin),
            user_addr,
            0);
        let repay_coin = coin::withdraw<CoinType>(sender, repay_coin);

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_deposit(sender, wormhole_message_fee, repay_coin, u16::from_u64(APPID), app_payload);
        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        debt_coin: u64,
        // punished person
        liquidate_user_id: u64,
        txid: vector<u8>,
    ) acquires LendingEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver);

        let app_payload = encode_app_payload(
            txid,
            LIQUIDATE,
            normal_amount<DebtCoinType>(debt_coin),
            receiver,
            liquidate_user_id
        );

        let debt_coin = coin::withdraw<DebtCoinType>(sender, debt_coin);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_deposit_and_withdraw<DebtCoinType, CollateralCoinType>(
            sender,
            wormhole_message_fee,
            debt_coin,
            u16::from_u64(APPID),
            app_payload,
        );
        let event_handle = borrow_global_mut<LendingEventHandle>(@lending_portal);
        event::emit_event(
            &mut event_handle.lending_started_handle,
            LendingStartedEvent {
                txid
            }
        )
    }

    public fun encode_app_payload(
        txid: vector<u8>,
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();

        assert!(vector::length(&txid) > 0, EINVALID_LENGTH);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&txid)));
        serialize_vector(&mut payload, txid);

        serialize_u64(&mut payload, amount);
        let receiver = encode_dola_address(receiver);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&receiver)));
        serialize_vector(&mut payload, receiver);
        serialize_u64(&mut payload, liquidate_user_id);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (vector<u8>, u8, u64, DolaAddress, u64) {
        let index = 0;
        let data_len;

        data_len = 2;
        let txid_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(txid_length);
        let txid = vector_slice(&app_payload, index, index + data_len);
        index = index + data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let receive_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(receive_length);
        let receiver = decode_dola_address(vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let liquidate_user_id = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (txid, call_type, amount, receiver, liquidate_user_id)
    }
}
