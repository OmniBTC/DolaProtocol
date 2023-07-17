module dola_protocol::remote_gov_codec {

    use std::vector;

    use dola_protocol::dola_address;
    use dola_protocol::dola_address::DolaAddress;
    use dola_protocol::serde;

    /// Errors
    const EINVALID_LENGTH: u64 = 1;

    /// Relayer op code
    const ADD_RELAYER: u8 = 0;

    const REMOVE_RELAYER: u8 = 1;


    /// === View Functions ===
    public fun get_add_relayer_opcode(): u8 {
        ADD_RELAYER
    }

    public fun get_remove_relayer_opcode(): u8 {
        REMOVE_RELAYER
    }

    /// === Helper Functions ===
    /// Encode and decode

    public fun encode_relayer_payload(
        relayer_address: DolaAddress,
        relayer_op: u8,
    ): vector<u8> {
        let relayer_payload = vector::empty<u8>();

        let relayer_address = dola_address::encode_dola_address(relayer_address);
        serde::serialize_u16(&mut relayer_payload, (vector::length(&relayer_address) as u16));
        serde::serialize_vector(&mut relayer_payload, relayer_address);

        serde::serialize_u8(&mut relayer_payload, relayer_op);

        relayer_payload
    }

    public fun decode_relayer_payload(payload: vector<u8>): (DolaAddress, u8) {
        let length = vector::length(&payload);
        let index = 0;
        let data_len;


        data_len = 2;
        let relayer_len = serde::deserialize_u16(&serde::vector_slice(&payload, index, index + data_len));

        index = index + data_len;

        data_len = (relayer_len as u64);
        let relayer_address = dola_address::decode_dola_address(
            serde::vector_slice(&payload, index, index + data_len)
        );
        index = index + data_len;

        data_len = 1;
        let relayer_op = serde::deserialize_u8(&serde::vector_slice(&payload, index, index + data_len));
        index = index + data_len;
        assert!(length == index, EINVALID_LENGTH);

        (relayer_address, relayer_op)
    }
}
