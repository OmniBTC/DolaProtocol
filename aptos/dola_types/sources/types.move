module dola_types::types {
    use std::vector;

    use serde::serde::{serialize_u16, serialize_vector, deserialize_u16, vector_slice};
    use std::bcs;
    use aptos_framework::util::address_from_bytes;
    use aptos_std::type_info;
    use std::string;
    use serde::u16::U16;
    use serde::u16;

    const DOLACHAINID: u64 = 0;

    /// Used to represent user address and pool address
    struct DolaAddress has copy, drop, store {
        dola_chain_id: U16,
        dola_address: vector<u8>
    }

    public fun dola_chain_id(dola_address: &DolaAddress): U16 {
        dola_address.dola_chain_id
    }

    public fun dola_address(dola_address: &DolaAddress): vector<u8> {
        dola_address.dola_address
    }

    public fun update_dola_chain_id(addr: DolaAddress, dola_chain_id: U16): DolaAddress {
        addr.dola_chain_id = dola_chain_id;
        addr
    }

    public fun update_dola_address(addr: DolaAddress, dola_address: vector<u8>): DolaAddress {
        addr.dola_address = dola_address;
        addr
    }

    public fun create_dola_address(dola_chain_id: U16, dola_address: vector<u8>): DolaAddress {
        DolaAddress { dola_chain_id, dola_address }
    }

    public fun convert_address_to_dola(addr: address): DolaAddress {
        DolaAddress {
            dola_chain_id: u16::from_u64(DOLACHAINID),
            dola_address: bcs::to_bytes(&addr)
        }
    }

    public fun convert_dola_to_address(addr: DolaAddress): address {
        address_from_bytes(addr.dola_address)
    }

    public fun convert_pool_to_dola<CoinType>(): DolaAddress {
        let dola_address = *string::bytes(&type_info::type_name<CoinType>());
        DolaAddress {
            dola_chain_id: u16::from_u64(DOLACHAINID),
            dola_address
        }
    }

    public fun convert_dola_to_pool(addr: DolaAddress): vector<u8> {
        addr.dola_address
    }

    public fun encode_dola_address(addr: DolaAddress): vector<u8> {
        let data = vector::empty();
        serialize_u16(&mut data, addr.dola_chain_id);
        serialize_vector(&mut data, addr.dola_address);
        data
    }

    public fun decode_dola_address(addr: vector<u8>): DolaAddress {
        let len = vector::length(&addr);
        let index = 0;
        let data_len;

        data_len = 2;
        let dola_chain_id = deserialize_u16(&vector_slice(&addr, index, index + data_len));
        index = index + data_len;

        let dola_address = vector_slice(&addr, index, len);
        DolaAddress {
            dola_chain_id,
            dola_address
        }
    }
}
