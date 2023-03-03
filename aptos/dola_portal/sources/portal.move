module dola_portal::portal {
    use std::bcs;
    use std::signer;
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event::{Self, EventHandle};

    use dola_types::types::{Self, DolaAddress};
    use omnipool::pool;
    use serde::serde;
    use serde::u16::{Self, U16};
    use serde::u256;
    use wormhole::state;
    use wormhole_bridge::bridge_pool;

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

    const AS_COLLATERAL: u8 = 7;

    const CANCEL_AS_COLLATERAL: u8 = 8;

    /// Events
    struct PortalEventHandle has key {
        nonce: u64,
        protocol_event_handle: EventHandle<ProtocolPortalEvent>,
        lending_event_handle: EventHandle<LendingPortalEvent>
    }

    struct ProtocolPortalEvent has drop, store {
        nonce: u64,
        sender: address,
        source_chain_id: U16,
        user_chain_id: U16,
        user_address: vector<u8>,
        call_type: u8
    }

    struct LendingPortalEvent has drop, store {
        nonce: u64,
        sender: address,
        dola_pool_address: vector<u8>,
        source_chain_id: U16,
        dst_chain_id: U16,
        receiver: vector<u8>,
        amount: u64,
        call_type: u8
    }

    public entry fun initialize(account: &signer) {
        assert!(signer::address_of(account) == @dola_portal, ENOT_DEPLOYER);
        move_to(account, PortalEventHandle {
            nonce: 0,
            protocol_event_handle: account::new_event_handle<ProtocolPortalEvent>(account),
            lending_event_handle: account::new_event_handle<LendingPortalEvent>(account)
        })
    }

    fun get_nonce(): u64 acquires PortalEventHandle {
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);
        let nonce = event_handle.nonce;
        event_handle.nonce = event_handle.nonce + 1;
        nonce
    }

    public entry fun as_collateral(
        sender: &signer,
        dola_pool_ids: vector<u64>,
    ) {
        bridge_pool::send_lending_helper_payload(sender, dola_pool_ids, AS_COLLATERAL);
    }

    public entry fun cancel_as_collateral(
        sender: &signer,
        dola_pool_ids: vector<u64>,
    ) {
        bridge_pool::send_lending_helper_payload(sender, dola_pool_ids, CANCEL_AS_COLLATERAL);
    }

    public entry fun binding(
        sender: &signer,
        dola_chain_id: u64,
        binded_address: vector<u8>,
    ) acquires PortalEventHandle {
        let nonce = get_nonce();
        bridge_pool::send_protocol_payload(sender, nonce, dola_chain_id, binded_address, BINDING);
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);
        event::emit_event(
            &mut event_handle.protocol_event_handle,
            ProtocolPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                user_chain_id: u16::from_u64(dola_chain_id),
                user_address: binded_address,
                call_type: BINDING
            }
        )
    }

    public entry fun unbinding(
        sender: &signer,
        dola_chain_id: u64,
        unbinded_address: vector<u8>
    ) acquires PortalEventHandle {
        let nonce = get_nonce();
        bridge_pool::send_protocol_payload(sender, nonce, dola_chain_id, unbinded_address, UNBINDING);
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);
        event::emit_event(
            &mut event_handle.protocol_event_handle,
            ProtocolPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                user_chain_id: u16::from_u64(dola_chain_id),
                user_address: unbinded_address,
                call_type: UNBINDING
            }
        )
    }

    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
    ) acquires PortalEventHandle {
        let user = types::convert_address_to_dola(signer::address_of(sender));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        let nonce = get_nonce();
        let amount = pool::normal_amount<CoinType>(deposit_coin);
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            SUPPLY,
            amount,
            user,
            0
        );
        let deposit_coin = coin::withdraw<CoinType>(sender, deposit_coin);

        bridge_pool::send_deposit(
            sender,
            wormhole_message_fee,
            deposit_coin,
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );
        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: types::get_dola_address(&types::convert_pool_to_dola<CoinType>()),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(0),
                receiver: bcs::to_bytes(&signer::address_of(sender)),
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
        let receiver = types::create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = get_nonce();
        let amount = pool::normal_amount<CoinType>(amount);
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            WITHDRAW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        let withdraw_pool = types::convert_pool_to_dola<CoinType>();

        bridge_pool::send_withdraw(
            sender,
            wormhole_message_fee,
            types::get_dola_chain_id(&withdraw_pool),
            types::get_dola_address(&withdraw_pool),
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: types::get_dola_address(&types::convert_pool_to_dola<CoinType>()),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(dst_chain),
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
        let receiver = types::create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = get_nonce();
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            WITHDRAW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        bridge_pool::send_withdraw(
            sender,
            wormhole_message_fee,
            u16::from_u64(dst_chain),
            pool,
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: pool,
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(dst_chain),
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
        let receiver = types::create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = get_nonce();
        let amount = pool::normal_amount<CoinType>(amount);
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            BORROW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let withdraw_pool = types::convert_pool_to_dola<CoinType>();

        bridge_pool::send_withdraw(
            sender,
            wormhole_message_fee,
            types::get_dola_chain_id(&withdraw_pool),
            types::get_dola_address(&withdraw_pool),
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: types::get_dola_address(&types::convert_pool_to_dola<CoinType>()),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(dst_chain),
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
        let receiver = types::create_dola_address(u16::from_u64(dst_chain), receiver_addr);

        let nonce = get_nonce();
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            BORROW,
            amount,
            receiver,
            0);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        bridge_pool::send_withdraw(
            sender,
            wormhole_message_fee,
            u16::from_u64(dst_chain),
            pool,
            u16::from_u64(LENDING_APP_ID),
            app_payload
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: pool,
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(dst_chain),
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
        let user_addr = types::convert_address_to_dola(signer::address_of(sender));

        let nonce = get_nonce();
        let amount = pool::normal_amount<CoinType>(repay_coin);
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            REPAY,
            amount,
            user_addr,
            0);
        let repay_coin = coin::withdraw<CoinType>(sender, repay_coin);

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        bridge_pool::send_deposit(sender, wormhole_message_fee, repay_coin, u16::from_u64(LENDING_APP_ID), app_payload);

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: types::get_dola_address(&types::convert_pool_to_dola<CoinType>()),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(0),
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount,
                call_type: REPAY
            }
        )
    }

    public entry fun liquidate<DebtCoinType>(
        sender: &signer,
        debt_amount: u64,
        liquidate_chain_id: u64,
        liquidate_pool_address: vector<u8>,
        // punished person
        liquidate_user_id: u64,
    ) acquires PortalEventHandle {
        let receiver = types::convert_address_to_dola(signer::address_of(sender));

        let nonce = get_nonce();
        let app_payload = encode_lending_app_payload(
            u16::from_u64(types::get_native_dola_chain_id()),
            nonce,
            LIQUIDATE,
            pool::normal_amount<DebtCoinType>(debt_amount),
            receiver, liquidate_user_id);

        let debt_coin = coin::withdraw<DebtCoinType>(sender, debt_amount);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        bridge_pool::send_deposit_and_withdraw<DebtCoinType>(
            sender,
            wormhole_message_fee,
            debt_coin,
            u16::from_u64(liquidate_chain_id),
            liquidate_pool_address,
            u16::from_u64(LENDING_APP_ID),
            app_payload,
        );

        let event_handle = borrow_global_mut<PortalEventHandle>(@dola_portal);

        event::emit_event(
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: types::get_dola_address(&types::convert_pool_to_dola<DebtCoinType>()),
                source_chain_id: u16::from_u64(types::get_native_dola_chain_id()),
                dst_chain_id: u16::from_u64(0),
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount: debt_amount,
                call_type: LIQUIDATE
            }
        )
    }

    public fun encode_lending_app_payload(
        source_chain_id: U16,
        nonce: u64,
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serde::serialize_u16(&mut payload, source_chain_id);
        serde::serialize_u64(&mut payload, nonce);

        serde::serialize_u256(&mut payload, u256::from_u64(amount));
        let receiver = types::encode_dola_address(receiver);
        serde::serialize_u16(&mut payload, u16::from_u64(vector::length(&receiver)));
        serde::serialize_vector(&mut payload, receiver);
        serde::serialize_u64(&mut payload, liquidate_user_id);
        serde::serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_lending_app_payload(app_payload: vector<u8>): (U16, u64, u8, u64, DolaAddress, u64) {
        let index = 0;
        let data_len;

        data_len = 2;
        let source_chain_id = serde::deserialize_u16(&serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = serde::deserialize_u64(&serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 32;
        let amount = serde::deserialize_u256(&serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let receive_length = serde::deserialize_u16(&serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = u16::to_u64(receive_length);
        let receiver = types::decode_dola_address(serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let liquidate_user_id = serde::deserialize_u64(&serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (source_chain_id, nonce, call_type, u256::as_u64(amount), receiver, liquidate_user_id)
    }
}
