module dola_portal::portal {
    use std::bcs::to_bytes;
    use std::hash::sha3_256;
    use std::signer;
    use std::vector;

    use aptos_framework::account::{new_event_handle, get_sequence_number};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::block::get_current_block_height;
    use aptos_framework::coin;
    use aptos_framework::event::{EventHandle, emit_event};

    use dola_types::types::{create_dola_address, decode_dola_address, DolaAddress, convert_address_to_dola, encode_dola_address, get_native_dola_chain_id, convert_pool_to_dola, dola_address};
    use omnipool::pool::normal_amount;
    use serde::serde::{serialize_u64, serialize_u8, deserialize_u8, vector_slice, deserialize_u64, serialize_u16, serialize_vector, deserialize_u16, serialize_address};
    use serde::u16::{Self, U16};
    use wormhole::state;
    use wormhole_bridge::bridge_pool::{send_deposit, send_withdraw, send_deposit_and_withdraw, send_withdraw_remote, send_binding, send_unbinding};

    /// Errors
    const EINVALID_LENGTH: u64 = 0;

    const ENOT_DEPLOYER: u64 = 1;

    /// Const
    const LENDING_APP_ID: u64 = 1;

    /// Call types for relayer call
    const SUPPLY: u8 = 0;

    const WITHDRAW: u8 = 1;

    const BORROW: u8 = 2;

    const REPAY: u8 = 3;

    const LIQUIDATE: u8 = 4;

    const BINDING: u8 = 5;

    const UNBINDING: u8 = 6;

    /// Events
    struct PortalEventHandle has key {
        protocol_event_handle: EventHandle<ProtocolPortalEvent>,
        lending_event_handle: EventHandle<LendingPortalEvent>
    }

    struct ProtocolPortalEvent has drop, store {
        nonce: vector<u8>,
        sender: address,
        send_chain_id: U16,
        user_chain_id: U16,
        user_address: vector<u8>,
        call_type: u8
    }

    struct LendingPortalEvent has drop, store {
        nonce: vector<u8>,
        sender: address,
        dola_pool_address: vector<u8>,
        send_chain_id: U16,
        receive_chain_id: U16,
        receiver: vector<u8>,
        amount: u64,
        call_type: u8
    }

    public entry fun initialize(account: &signer) {
        assert!(signer::address_of(account) == @dola_portal, ENOT_DEPLOYER);
        move_to(account, PortalEventHandle {
            protocol_event_handle: new_event_handle<ProtocolPortalEvent>(account),
            lending_event_handle: new_event_handle<LendingPortalEvent>(account)
        })
    }

    public entry fun binding(
        sender: &signer,
        dola_chain_id: u64,
        bind_address: vector<u8>,
    ) acquires PortalEventHandle {
        send_binding(sender, dola_chain_id, bind_address);
        let nonce = generate_nonce(sender);
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);
        emit_event(
            &mut event_handle.protocol_event_handle,
            ProtocolPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                user_chain_id: u16::from_u64(dola_chain_id),
                user_address: bind_address,
                call_type: BINDING
            }
        )
    }

    public entry fun unbinding(
        sender: &signer,
        dola_chain_id: u64,
        unbind_address: vector<u8>
    ) acquires PortalEventHandle {
        send_unbinding(sender, dola_chain_id, unbind_address);
        let nonce = generate_nonce(sender);
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);
        emit_event(
            &mut event_handle.protocol_event_handle,
            ProtocolPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                user_chain_id: u16::from_u64(dola_chain_id),
                user_address: unbind_address,
                call_type: UNBINDING
            }
        )
    }

    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
    ) acquires PortalEventHandle {
        let user = convert_address_to_dola(signer::address_of(sender));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        let nonce = generate_nonce(sender);
        let amount = normal_amount<CoinType>(deposit_coin);
        let app_payload = encode_app_payload(
            nonce,
            SUPPLY,
            amount,
            user,
            0
        );
        let deposit_coin = coin::withdraw<CoinType>(sender, deposit_coin);

        send_deposit(sender, wormhole_message_fee, deposit_coin, u16::from_u64(LENDING_APP_ID), app_payload);
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address(&convert_pool_to_dola<CoinType>()),
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                receive_chain_id: u16::from_u64(0),
                receiver: to_bytes(&signer::address_of(sender)),
                amount,
                call_type: SUPPLY
            }
        )
    }

    public entry fun withdraw_local<CoinType>(
        sender: &signer,
        receiver_addr: vector<u8>,
        dst_chain: u64,
        amount: u64,
    ) acquires PortalEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = generate_nonce(sender);
        let amount = normal_amount<CoinType>(amount);
        let app_payload = encode_app_payload(
            nonce,
            WITHDRAW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        send_withdraw<CoinType>(sender, wormhole_message_fee, u16::from_u64(LENDING_APP_ID), app_payload);

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address(&convert_pool_to_dola<CoinType>()),
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                receive_chain_id: u16::from_u64(dst_chain),
                receiver: receiver_addr,
                amount,
                call_type: WITHDRAW
            }
        )
    }

    public entry fun withdraw_remote(
        sender: &signer,
        receiver_addr: vector<u8>,
        pool: vector<u8>,
        dst_chain: u64,
        amount: u64,
    ) acquires PortalEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = generate_nonce(sender);
        let app_payload = encode_app_payload(
            nonce,
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
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: pool,
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                receive_chain_id: u16::from_u64(dst_chain),
                receiver: receiver_addr,
                amount,
                call_type: WITHDRAW
            }
        )
    }

    public entry fun borrow_local<CoinType>(
        sender: &signer,
        receiver_addr: vector<u8>,
        dst_chain: u64,
        amount: u64,
    ) acquires PortalEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = generate_nonce(sender);
        let amount = normal_amount<CoinType>(amount);
        let app_payload = encode_app_payload(
            nonce,
            BORROW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_withdraw<CoinType>(sender, wormhole_message_fee, u16::from_u64(LENDING_APP_ID), app_payload);

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address(&convert_pool_to_dola<CoinType>()),
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                receive_chain_id: u16::from_u64(dst_chain),
                receiver: receiver_addr,
                amount,
                call_type: BORROW
            }
        )
    }

    public entry fun borrow_remote(
        sender: &signer,
        receiver_addr: vector<u8>,
        pool: vector<u8>,
        dst_chain: u64,
        amount: u64,
    ) acquires PortalEventHandle {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = generate_nonce(sender);
        let app_payload = encode_app_payload(
            nonce,
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
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: pool,
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                receive_chain_id: u16::from_u64(dst_chain),
                receiver: receiver_addr,
                amount,
                call_type: BORROW
            }
        )
    }

    public entry fun repay<CoinType>(
        sender: &signer,
        repay_coin: u64,
    ) acquires PortalEventHandle {
        let user_addr = convert_address_to_dola(signer::address_of(sender));

        let nonce = generate_nonce(sender);
        let amount = normal_amount<CoinType>(repay_coin);
        let app_payload = encode_app_payload(
            nonce,
            REPAY,
            amount,
            user_addr,
            0);
        let repay_coin = coin::withdraw<CoinType>(sender, repay_coin);

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_deposit(sender, wormhole_message_fee, repay_coin, u16::from_u64(LENDING_APP_ID), app_payload);

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address(&convert_pool_to_dola<CoinType>()),
                send_chain_id: u16::from_u64(get_native_dola_chain_id()),
                receive_chain_id: u16::from_u64(0),
                receiver: to_bytes(&signer::address_of(sender)),
                amount,
                call_type: REPAY
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
    ) {
        let receiver = create_dola_address(u16::from_u64(dst_chain), receiver);

        let nonce = generate_nonce(sender);
        let app_payload = encode_app_payload(
            nonce,
            LIQUIDATE,
            normal_amount<DebtCoinType>(debt_coin),
            receiver, liquidate_user_id);

        let debt_coin = coin::withdraw<DebtCoinType>(sender, debt_coin);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        send_deposit_and_withdraw<DebtCoinType, CollateralCoinType>(
            sender,
            wormhole_message_fee,
            debt_coin,
            u16::from_u64(LENDING_APP_ID),
            app_payload,
        );
    }

    public fun encode_app_payload(
        nonce: vector<u8>,
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serialize_u16(&mut payload, u16::from_u64(vector::length(&nonce)));
        serialize_vector(&mut payload, nonce);

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
        let nonce_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));

        index = index + data_len;

        data_len = u16::to_u64(nonce_length);
        let nonce = vector_slice(&app_payload, index, index + data_len);
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

        (nonce, call_type, amount, receiver, liquidate_user_id)
    }

    fun generate_nonce(sender: &signer): vector<u8> {
        let height = get_current_block_height();
        let nonce = get_sequence_number(signer::address_of(sender));
        let content = vector::empty<u8>();
        serialize_u64(&mut content, height);
        serialize_u64(&mut content, nonce);
        serialize_address(&mut content, signer::address_of(sender));
        sha3_256(content)
    }
}
