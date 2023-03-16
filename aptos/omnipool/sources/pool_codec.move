// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Codecing for pool contracts
module omnipool::pool_codec {
    use std::vector;

    use dola_types::dola_address::{Self, DolaAddress};
    use serde::serde;

    /// Errors
    // Invalid length of Payload
    const EINVALID_LENGTH: u64 = 0;

    // Wrong call type
    const EINVALID_CALL_TYPE: u64 = 1;

    /// Pool call type
    const POOL_DEPOSIT: u8 = 0;

    const POOL_WITHDRAW: u8 = 1;

    const POOL_SEND_MESSAGE: u8 = 2;

    const POOL_REGISTER_OWNER: u8 = 3;

    const POOL_REGISTER_SPENDER: u8 = 4;

    const POOL_DELETE_OWNER: u8 = 5;

    const POOL_DELETE_SPENDER: u8 = 6;

    /// Getter

    public fun get_deposit_type(): u8 {
        POOL_DEPOSIT
    }

    public fun get_withdraw_type(): u8 {
        POOL_WITHDRAW
    }

    public fun get_send_message_type(): u8 {
        POOL_SEND_MESSAGE
    }

    public fun get_register_owner_type(): u8 {
        POOL_REGISTER_OWNER
    }

    public fun get_register_spender_type(): u8 {
        POOL_REGISTER_SPENDER
    }

    public fun get_delete_owner_type(): u8 {
        POOL_DELETE_OWNER
    }

    public fun get_delete_spender_type(): u8 {
        POOL_DELETE_SPENDER
    }

    /// Encode and decode

    /// Encoding of Pool Messages with Funding
    public fun encode_deposit_payload(
        pool_address: DolaAddress,
        user_address: DolaAddress,
        amount: u64,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, app_id);

        let pool_address = dola_address::encode_dola_address(pool_address);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_address) as u16));
        serde::serialize_vector(&mut pool_payload, pool_address);

        let user_address = dola_address::encode_dola_address(user_address);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_address) as u16));
        serde::serialize_vector(&mut pool_payload, user_address);

        serde::serialize_u64(&mut pool_payload, amount);

        serde::serialize_u8(&mut pool_payload, POOL_DEPOSIT);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serde::serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// Decoding of Pool Messages with Funding
    public fun decode_deposit_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, u16, u8, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_address = dola_address::decode_dola_address(
            serde::vector_slice(&pool_payload, index, index + data_len)
        );
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_address = dola_address::decode_dola_address(
            serde::vector_slice(&pool_payload, index, index + data_len)
        );
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let pool_call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = serde::vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(pool_call_type == POOL_DEPOSIT, EINVALID_CALL_TYPE);
        assert!(length == index, EINVALID_LENGTH);

        (pool_address, user_address, amount, app_id, pool_call_type, app_payload)
    }

    /// Encoding of Pool Messages with Funds Withdrawal
    public fun encode_withdraw_payload(
        source_chain_id: u16,
        nonce: u64,
        pool_address: DolaAddress,
        user_address: DolaAddress,
        amount: u64
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        // encode nonce
        serde::serialize_u16(&mut pool_payload, source_chain_id);
        serde::serialize_u64(&mut pool_payload, nonce);

        let pool_address = dola_address::encode_dola_address(pool_address);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_address) as u16));
        serde::serialize_vector(&mut pool_payload, pool_address);

        let user_address = dola_address::encode_dola_address(user_address);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_address) as u16));
        serde::serialize_vector(&mut pool_payload, user_address);

        serde::serialize_u64(&mut pool_payload, amount);

        serde::serialize_u8(&mut pool_payload, POOL_WITHDRAW);

        pool_payload
    }

    /// Decoding of Pool Messages with Funds Withdrawal
    public fun decode_withdraw_payload(
        pool_payload: vector<u8>
    ): (u16, u64, DolaAddress, DolaAddress, u64, u8) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let source_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_address = dola_address::decode_dola_address(
            serde::vector_slice(&pool_payload, index, index + data_len)
        );

        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_address = dola_address::decode_dola_address(
            serde::vector_slice(&pool_payload, index, index + data_len)
        );
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let pool_call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(pool_call_type == POOL_WITHDRAW, EINVALID_CALL_TYPE);

        assert!(length == index, EINVALID_LENGTH);

        (source_chain_id, nonce, pool_address, user_address, amount, pool_call_type)
    }

    /// Pool message encode that do not involve incoming or outgoing funds
    public fun encode_send_message_payload(
        user_address: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, app_id);

        let user_address = dola_address::encode_dola_address(user_address);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_address) as u16));
        serde::serialize_vector(&mut pool_payload, user_address);

        serde::serialize_u8(&mut pool_payload, POOL_SEND_MESSAGE);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serde::serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// Pool message decode that do not involve incoming or outgoing funds
    public fun decode_send_message_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, u16, u8, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_address = dola_address::decode_dola_address(
            serde::vector_slice(&pool_payload, index, index + data_len)
        );
        index = index + data_len;

        data_len = 1;
        let pool_call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        let app_payload = vector::empty<u8>();
        if (length > index) {
            data_len = 2;
            let app_payload_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
            index = index + data_len;

            data_len = (app_payload_len as u64);
            app_payload = serde::vector_slice(&pool_payload, index, index + data_len);
            index = index + data_len;
        };

        assert!(pool_call_type == POOL_SEND_MESSAGE, EINVALID_CALL_TYPE);
        assert!(length == index, EINVALID_LENGTH);

        (user_address, app_id, pool_call_type, app_payload)
    }


    /// Encode pool manage owner from sui to branch
    public fun encode_manage_pool_payload(
        dola_chain_id: u16,
        dola_contract: u256,
        pool_call_type: u8
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, dola_chain_id);

        serde::serialize_u256(&mut pool_payload, dola_contract);

        serde::serialize_u8(&mut pool_payload, pool_call_type);

        pool_payload
    }

    /// Decode pool register owner from sui to branch
    public fun decode_manage_pool_payload(pool_payload: vector<u8>): (u16, u256, u8) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let dola_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 32;
        let dola_contract = serde::deserialize_u256(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let pool_call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);

        (dola_chain_id, dola_contract, pool_call_type)
    }

    #[test]
    public fun test_pool_codec() {
        // test encode and decode deposit payload
        let pool_1 = dola_address::convert_address_to_dola(@0x101);
        let user_1 = dola_address::convert_address_to_dola(@0x102);
        let amount_1 = 100;
        let app_id_1 = 0;
        let app_payload_1 = vector[0];
        let deposit_payload = encode_deposit_payload(
            pool_1,
            user_1,
            amount_1,
            app_id_1,
            app_payload_1
        );
        let (pool_address, user_address, amount, app_id, pool_call_type, app_payload) = decode_deposit_payload(
            deposit_payload
        );
        assert!(pool_address == pool_1, 101);
        assert!(user_address == user_1, 102);
        assert!(amount == amount_1, 103);
        assert!(app_id == app_id_1, 104);
        assert!(pool_call_type == POOL_DEPOSIT, 105);
        assert!(app_payload == app_payload_1, 106);

        // test encode and decode withdraw payload
        let pool_2 = dola_address::convert_address_to_dola(@0x201);
        let user_2 = dola_address::convert_address_to_dola(@0x202);
        let amount_2 = 100;
        let source_chain_id_2 = 1;
        let nonce_2 = 1;
        let withdraw_payload = encode_withdraw_payload(
            source_chain_id_2,
            nonce_2,
            pool_2,
            user_2,
            amount_2
        );
        let (source_chain_id, nonce, pool_address, user_address, amount, pool_call_type) = decode_withdraw_payload(
            withdraw_payload
        );
        assert!(source_chain_id == source_chain_id_2, 201);
        assert!(nonce == nonce_2, 202);
        assert!(pool_address == pool_2, 203);
        assert!(user_address == user_2, 204);
        assert!(amount == amount_2, 205);
        assert!(pool_call_type == POOL_WITHDRAW, 206);

        // test encode and decode send_message_payload
        let user_3 = dola_address::convert_address_to_dola(@0x301);
        let app_id_3 = 2;
        let app_payload_3 = vector[2];
        let send_message_payload = encode_send_message_payload(
            user_3,
            app_id_3,
            app_payload_3
        );
        let (user_address, app_id, pool_call_type, app_payload) = decode_send_message_payload(send_message_payload);
        assert!(user_address == user_3, 301);
        assert!(app_id == app_id_3, 302);
        assert!(pool_call_type == POOL_SEND_MESSAGE, 303);
        assert!(app_payload == app_payload_3, 304);

        // test encode and decode manage_pool_payload
        let dola_chain_id_4 = 4;
        let dola_contract_4 = 4;
        let pool_call_type_4 = POOL_REGISTER_OWNER;
        let manager_pool_payload = encode_manage_pool_payload(
            dola_chain_id_4,
            dola_contract_4,
            pool_call_type_4
        );
        let (dola_chain_id, dola_contract, pool_call_type) = decode_manage_pool_payload(manager_pool_payload);
        assert!(dola_chain_id == dola_chain_id_4, 401);
        assert!(dola_contract == dola_contract_4, 402);
        assert!(pool_call_type == pool_call_type_4, 403);
    }
}
