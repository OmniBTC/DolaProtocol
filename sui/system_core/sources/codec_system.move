module system_core::codec_system {

    use dola_types::dola_address::{Self, DolaAddress};
    use std::vector;
    use serde::serde;

    /// Errors
    /// Invalid length of Payload
    const EINVALID_LENGTH: u64 = 0;

    /// Wrong call type
    const EINVALID_CALL_TYPE: u64 = 1;

    /// System call type

    const BINDING: u8 = 0;

    const UNBINDING: u8 = 1;

    /// Getter

    public fun get_binding_type(): u8 {
        BINDING
    }

    public fun get_unbinding_type(): u8 {
        UNBINDING
    }

    /// Encode and decode

    /// Encode binding or unbinding
    public fun encode_bind_payload(
        source_chain_id: u16,
        nonce: u64,
        system_call_type: u8,
        bind_address: DolaAddress
    ): vector<u8> {
        let payload = vector::empty<u8>();

        serde::serialize_u16(&mut payload, source_chain_id);
        serde::serialize_u64(&mut payload, nonce);

        let bind_address = dola_address::encode_dola_address(bind_address);
        serde::serialize_u16(&mut payload, (vector::length(&bind_address) as u16));
        serde::serialize_vector(&mut payload, bind_address);

        serde::serialize_u8(&mut payload, system_call_type);
        payload
    }

    /// Decode binding or unbinding
    public fun decode_bind_payload(payload: vector<u8>): (u16, u64, DolaAddress, u8) {
        let length = vector::length(&payload);
        let index = 0;
        let data_len;

        data_len = 2;
        let source_chain_id = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let nonce = serde::deserialize_u64(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let bind_len = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = (bind_len as u64);
        let bind_address = dola_address::decode_dola_address(serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let system_call_type = serde::deserialize_u8(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;

        assert!(length == index, EINVALID_LENGTH);
        (source_chain_id, nonce, bind_address, system_call_type)
    }
}
