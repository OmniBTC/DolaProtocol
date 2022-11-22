module wormhole_bridge::helper {
    use std::vector;

    use serde::serde::{serialize_u16, serialize_vector, deserialize_u16, vector_slice};
    use serde::u16;

    public fun encode_deposit_and_withdraw(deposit_msg: vector<u8>, withdraw_msg: vector<u8>) {
        let payload = vector::empty<u8>();
        serialize_u16(&mut payload, u16::from_u64(vector::length(&deposit_msg)));
        serialize_vector(&mut payload, deposit_msg);
        serialize_u16(&mut payload, u16::from_u64(vector::length(&withdraw_msg)));
        serialize_vector(&mut payload, withdraw_msg);
    }

    public fun decode_deposit_and_withdraw(msg: vector<u8>): (vector<u8>, vector<u8>) {
        let index = 0;
        let data_len;

        data_len = 2;
        let deposit_len = u16::to_u64(deserialize_u16(&vector_slice(&msg, index, index + data_len)));
        index = index + data_len;

        data_len = deposit_len;
        let deposit_msg = vector_slice(&msg, index, index + data_len);
        index = index + data_len;

        data_len = 2;
        let withdraw_len = u16::to_u64(deserialize_u16(&vector_slice(&msg, index, index + data_len)));
        index = index + data_len;

        data_len = deposit_len;
        let withdraw_msg = vector_slice(&msg, index, index + data_len);
        index = index + data_len;

        (deposit_msg, withdraw_msg)
    }
}
