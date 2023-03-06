module omnipool::codec_pool {
    use dola_types::types::DolaAddress;
    use std::vector;
    use dola_types::types;
    use serde::serde;

    /// Errors
    const EINVALID_LENGTH: u64 = 0;

    const EINVALID_CALL_TYPE: u64 = 1;

    /// Call type
    const POOL_WITHDRAW: u8 = 1;

    const POOL_REGISTER_OWNER: u8 = 2;

    const POOL_REGISTER_SPENDER: u8 = 3;

    const POOL_DELETE_OWNER: u8 = 4;

    const POOL_DELETE_SPENDER: u8 = 5;


    /// encode deposit msg
    public fun encode_send_deposit_payload(
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        amount: u64,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_addr) as u16));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_addr) as u16));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u64(&mut pool_payload, amount);

        serde::serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serde::serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode deposit msg
    public fun decode_send_deposit_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
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

        assert!(length == index, EINVALID_LENGTH);

        (pool_addr, user_addr, amount, app_id, app_payload)
    }

    /// encode whihdraw msg
    public fun encode_send_withdraw_payload(
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_addr) as u16));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_addr) as u16));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u16(&mut pool_payload, app_id);

        if (vector::length(&app_payload) > 0) {
            serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
            serde::serialize_vector(&mut pool_payload, app_payload);
        };
        pool_payload
    }

    /// decode withdraw msg
    public fun decode_send_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (pool_len as u64);
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
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

        assert!(length == index, EINVALID_LENGTH);

        (pool_addr, user_addr, app_id, app_payload)
    }

    public fun encode_send_deposit_and_withdraw_payload(
        deposit_pool: DolaAddress,
        deposit_user: DolaAddress,
        deposit_amount: u64,
        withdraw_pool: DolaAddress,
        app_id: u16,
        app_payload: vector<u8>
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        let deposit_pool = types::encode_dola_address(deposit_pool);
        serde::serialize_u16(&mut pool_payload, (vector::length(&deposit_pool) as u16));
        serde::serialize_vector(&mut pool_payload, deposit_pool);

        let deposit_user = types::encode_dola_address(deposit_user);
        serde::serialize_u16(&mut pool_payload, (vector::length(&deposit_user) as u16));
        serde::serialize_vector(&mut pool_payload, deposit_user);

        serde::serialize_u64(&mut pool_payload, deposit_amount);

        let withdraw_pool = types::encode_dola_address(withdraw_pool);
        serde::serialize_u16(&mut pool_payload, (vector::length(&withdraw_pool) as u16));
        serde::serialize_vector(&mut pool_payload, withdraw_pool);

        serde::serialize_u16(&mut pool_payload, app_id);

        serde::serialize_u16(&mut pool_payload, (vector::length(&app_payload) as u16));
        serde::serialize_vector(&mut pool_payload, app_payload);

        pool_payload
    }

    public fun decode_send_deposit_and_withdraw_payload(
        pool_payload: vector<u8>
    ): (DolaAddress, DolaAddress, u64, DolaAddress, u16, vector<u8>) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let deposit_pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = (deposit_pool_len as u64);
        let deposit_pool = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let deposit_user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (deposit_user_len as u64);
        let deposit_user = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let deposit_amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let withdraw_pool_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (withdraw_pool_len as u64);
        let withdraw_pool = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let app_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
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

        assert!(length == index, EINVALID_LENGTH);

        (deposit_pool, deposit_user, deposit_amount, withdraw_pool, app_id, app_payload)
    }

    /// encode withdraw msg
    public fun encode_receive_withdraw_payload(
        source_chain_id: u16,
        nonce: u64,
        pool_addr: DolaAddress,
        user_addr: DolaAddress,
        amount: u64
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        // encode nonce
        serde::serialize_u16(&mut pool_payload, source_chain_id);
        serde::serialize_u64(&mut pool_payload, nonce);

        let pool_addr = types::encode_dola_address(pool_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&pool_addr) as u16));
        serde::serialize_vector(&mut pool_payload, pool_addr);

        let user_addr = types::encode_dola_address(user_addr);
        serde::serialize_u16(&mut pool_payload, (vector::length(&user_addr) as u16));
        serde::serialize_vector(&mut pool_payload, user_addr);

        serde::serialize_u64(&mut pool_payload, amount);

        serde::serialize_u8(&mut pool_payload, POOL_WITHDRAW);

        pool_payload
    }

    /// decode withdraw msg
    public fun decode_receive_withdraw_payload(
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
        let pool_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));

        index = index + data_len;

        data_len = 2;
        let user_len = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = (user_len as u64);
        let user_addr = types::decode_dola_address(serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let amount = serde::deserialize_u64(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(call_type == POOL_WITHDRAW, EINVALID_CALL_TYPE);

        assert!(length == index, EINVALID_LENGTH);

        (source_chain_id, nonce, pool_addr, user_addr, amount, call_type)
    }

    /// encode withdraw msg
    public fun encode_register_owner_payload(
        doal_chain_id: u16,
        dola_contract: u256
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, doal_chain_id);

        serde::serialize_u256(&mut pool_payload, dola_contract);

        serde::serialize_u8(&mut pool_payload, POOL_REGISTER_OWNER);

        pool_payload
    }

    /// decode withdraw msg
    public fun decode_register_owner_payload(pool_payload: vector<u8>): (u16, u256, u8) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let doal_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 32;
        let dola_contract = serde::deserialize_u256(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(call_type == POOL_REGISTER_OWNER, EINVALID_CALL_TYPE);

        assert!(length == index, EINVALID_LENGTH);

        (doal_chain_id, dola_contract, call_type)
    }

    /// encode withdraw msg
    public fun encode_register_spender_payload(
        doal_chain_id: u16,
        dola_contract: u256
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, doal_chain_id);

        serde::serialize_u256(&mut pool_payload, dola_contract);

        serde::serialize_u8(&mut pool_payload, POOL_REGISTER_SPENDER);

        pool_payload
    }

    /// decode withdraw msg
    public fun decode_register_spender_payload(pool_payload: vector<u8>): (u16, u256, u8) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let doal_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 32;
        let dola_contract = serde::deserialize_u256(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(call_type == POOL_REGISTER_SPENDER, EINVALID_CALL_TYPE);
        assert!(length == index, EINVALID_LENGTH);

        (doal_chain_id, dola_contract, call_type)
    }

    /// encode withdraw msg
    public fun encode_delete_owner_payload(
        doal_chain_id: u16,
        dola_contract: u256
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, doal_chain_id);

        serde::serialize_u256(&mut pool_payload, dola_contract);

        serde::serialize_u8(&mut pool_payload, POOL_DELETE_OWNER);

        pool_payload
    }

    /// decode withdraw msg
    public fun decode_delete_owner_payload(pool_payload: vector<u8>): (u16, u256, u8) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let doal_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 32;
        let dola_contract = serde::deserialize_u256(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(call_type == POOL_DELETE_OWNER, EINVALID_CALL_TYPE);
        assert!(length == index, EINVALID_LENGTH);

        (doal_chain_id, dola_contract, call_type)
    }

    /// encode withdraw msg
    public fun encode_delete_spender_payload(
        doal_chain_id: u16,
        dola_contract: u256
    ): vector<u8> {
        let pool_payload = vector::empty<u8>();

        serde::serialize_u16(&mut pool_payload, doal_chain_id);

        serde::serialize_u256(&mut pool_payload, dola_contract);

        serde::serialize_u8(&mut pool_payload, POOL_DELETE_SPENDER);

        pool_payload
    }

    /// decode withdraw msg
    public fun decode_delete_spender_payload(pool_payload: vector<u8>): (u16, u256, u8) {
        let length = vector::length(&pool_payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let doal_chain_id = serde::deserialize_u16(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 32;
        let dola_contract = serde::deserialize_u256(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = serde::deserialize_u8(&serde::vector_slice(&pool_payload, index, index + data_len));
        index = index + data_len;

        assert!(call_type == POOL_DELETE_SPENDER, EINVALID_CALL_TYPE);
        assert!(length == index, EINVALID_LENGTH);

        (doal_chain_id, dola_contract, call_type)
    }
}
