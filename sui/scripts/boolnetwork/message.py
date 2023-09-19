from __future__ import annotations

import json
import logging
from typing import Union
import eth_abi
from eth_abi.encoding import encode_uint_256
from eth_abi.registry import BaseEquals, encoding
from eth_abi.utils.padding import zpad_right


class NewByteStringEncoder(encoding.ByteStringEncoder):
    is_dynamic = True

    @classmethod
    def encode(cls, value):
        cls.validate_value(value)
        value_length = len(value)

        encoded_size = encode_uint_256(value_length)

        if value_length == 0:
            return encoded_size

        ceil32 = (
            value_length
            if value_length % 32 == 0
            else value_length + 32 - (value_length % 32)
        )
        padded_value = zpad_right(value, ceil32)

        return encoded_size + padded_value


eth_abi.abi.registry.unregister_encoder(
    BaseEquals("bytes", with_sub=False),
)

eth_abi.abi.registry.register_encoder(
    BaseEquals("bytes", with_sub=False), NewByteStringEncoder
)


def convert_to_cross_id(tx_uid: Union[str, bytes]):
    """
    :param tx_uid: "0x000001440000a4b1000000000000000000000000000000000000000000000036"
    :return: "324:42161:54"
    """
    if type(tx_uid) == str:
        tx_uid = tx_uid[2:] if tx_uid.startswith("0x") else tx_uid
        bytes32 = bytes.fromhex(tx_uid)
    else:
        assert len(tx_uid) == 32, tx_uid
        bytes32 = tx_uid

    source_chain = int.from_bytes(bytes32[:4], "big")
    target_chain = int.from_bytes(bytes32[4:8], "big")
    nonce = int.from_bytes(bytes32[8:], "big")

    return f"{source_chain}:{target_chain}:{nonce}"


def convert_to_uid(uid: str):
    """
    :param uid: "324:42161:54"
    :return: "0x000001440000a4b1000000000000000000000000000000000000000000000036"
    """
    tokens = uid.split(":")
    assert len(tokens) == 3, tokens

    source_chain = int(tokens[0])
    target_chain = int(tokens[1])
    nonce = int(tokens[2])

    uid = source_chain << 32
    uid += target_chain
    uid = uid << 192
    uid += nonce

    uid_bytes = uid.to_bytes(length=32, byteorder="big", signed=False)

    return f"0x{uid_bytes.hex()}"


class Message:
    # On EVM
    # struct Message {
    #     bytes32 txUniqueIdentification;
    #     bytes32 crossType;
    #     bytes32 srcAnchor;
    #     bytes bnExtraFeed;
    #     bytes32 dstAnchor;
    #     bytes payload;
    # }
    # On Sui
    # struct Message has copy, drop {
    #     tx_unique_identification: u256,
    #     cross_type: vector<u8>,
    #     src_anchor: address,
    #     dst_anchor: address,
    #     bn_extra_feed: vector<u8>,
    #     payload: vector<u8>,
    # }

    MessageABI = ["bytes32", "bytes32", "bytes32", "bytes", "bytes32", "bytes"]

    def __init__(self, msg: bytes, to_sui: bool):
        if to_sui:
            self._decode_bcs(msg)
            self.to_sui = True
            self.origin = msg
        else:
            self._decode_rlp(msg[32:])
            self.to_sui = False
            self.origin = msg[32:]

    def __str__(self):
        return json.dumps(self.format_json(), indent=2)

    def __repr__(self):
        return self.__str__()

    def encode(self):
        if self.to_sui:
            return self._encode_bcs()
        else:
            return self._encode_rlp()

    def _decode_rlp(self, msg: bytes):
        (
            self.txUniqueIdentification,
            self.crossType,
            self.srcAnchor,
            self.bnExtraFeed,
            self.dstAnchor,
            self.payload,
        ) = eth_abi.decode(self.MessageABI, msg)

    def _encode_rlp(self):
        output = eth_abi.encode(
            self.MessageABI,
            (
                self.txUniqueIdentification,
                self.crossType,
                self.srcAnchor,
                self.bnExtraFeed,
                self.dstAnchor,
                self.payload,
            ),
        )

        assert self.origin == output, str(self)

        return output

    @classmethod
    def _decode_u32_from_uleb128(cls, data: bytearray):
        value = 0
        index = 0

        for shift in range(0, 32, 7):
            byte = data[index]
            value |= (byte & 0x7F) << shift
            index += 1

            if not (byte & 0x80):
                break

        return value, index

    @classmethod
    def _encode_u32_to_uleb128(cls, value: int):
        output = bytearray()
        while value >= 0x80:
            # Write 7 (lowest) bits of data and set the 8th bit to 1.
            byte = value & 0x7F
            output.append(byte | 0x80)
            value >>= 7

        # Write the remaining bits of data and set the highest bit to 0.
        output.append(value & 0x7F)

        return output

    @classmethod
    def _decode_bytes(cls, data: bytearray):
        length, index = cls._decode_u32_from_uleb128(data)

        # print(length, index, len(data[index:]), f"{list(data[index:])}")

        assert length <= len(data[index:]), length

        return data[index : index + length], index + length

    @classmethod
    def _encode_bytes(cls, data: bytes):
        output = bytearray()

        output += cls._encode_u32_to_uleb128(len(data))
        output += data

        return output

    def _decode_bcs(self, msg: bytes):
        # struct Message has copy, drop {
        #     tx_unique_identification: u256,
        #     cross_type: vector<u8>,
        #     src_anchor: address,
        #     dst_anchor: address,
        #     bn_extra_feed: vector<u8>,
        #     payload: vector<u8>,
        # }

        bytes_array = bytearray(msg)
        next_index = 0

        self.txUniqueIdentification = bytes_array[:32]
        # evm big endian => sui little endian
        self.txUniqueIdentification.reverse()

        next_index += 32

        self.crossType, length = Message._decode_bytes(bytes_array[next_index:])
        next_index += length

        self.srcAnchor = bytes_array[next_index : next_index + 32]
        next_index += 32

        self.dstAnchor = bytes_array[next_index : next_index + 32]
        next_index += 32

        self.bnExtraFeed, length = Message._decode_bytes(bytes_array[next_index:])
        next_index += length

        self.payload, length = Message._decode_bytes(bytes_array[next_index:])
        next_index += length

        assert next_index == len(msg), next_index

    def _encode_bcs(self):
        # struct Message has copy, drop {
        #     tx_unique_identification: u256,
        #     cross_type: vector<u8>,
        #     src_anchor: address,
        #     dst_anchor: address,
        #     bn_extra_feed: vector<u8>,
        #     payload: vector<u8>,
        # }
        output = bytearray()

        output += self.txUniqueIdentification
        output.reverse()

        output += Message._encode_bytes(self.crossType)

        output += self.srcAnchor

        output += self.dstAnchor

        output += Message._encode_bytes(self.bnExtraFeed)

        output += Message._encode_bytes(self.payload)

        assert self.origin == output, str(self)

        return output

    def format_json(self):
        return {
            "to_sui": self.to_sui,
            "txUniqueIdentification": "0x" + bytes(self.txUniqueIdentification).hex(),
            "crossType": "0x" + bytes(self.crossType).hex(),
            "srcAnchor": "0x" + bytes(self.srcAnchor).hex(),
            "bnExtraFeed": "0x" + bytes(self.bnExtraFeed).hex(),
            "dstAnchor": "0x" + bytes(self.dstAnchor).hex(),
            "payload": "0x" + bytes(self.payload).hex(),
            "origin": "0x" + bytes(self.origin).hex(),
        }

    def tx_uid(self):
        return "0x" + bytes(self.txUniqueIdentification).hex()

    def cross_id(self):
        return convert_to_cross_id(self.txUniqueIdentification)


class EventSubmitTransaction:
    def __init__(self, block_num, block_hash, event):
        self.verify_hash = None
        self.cid = None
        self.block_num = block_num
        self.block_hash = block_hash
        self.origin_event = event

        self.get_cid_hash(event)

    def __str__(self):
        return json.dumps(self.format_json())

    def __repr__(self):
        return json.dumps(self.format_json())

    def format_json(self):
        return {
            "blockNum": self.block_num,
            "blockHash": self.block_hash,
            "event": self.origin_event,
        }

    def get_cid_hash(self, event):
        format_str = (
            format(f"{event}")
            .replace("'", '"')
            .replace("(", "[")
            .replace(")", "]")
            .replace("None", '""')
        )

        format_json = json.loads(format_str)

        cid = format_json["event"]["attributes"][0]
        if type(cid) is dict:
            cid = cid["value"]

        verify_hash = format_json["event"]["attributes"][3]
        if type(verify_hash) is dict:
            verify_hash = verify_hash["value"]

        self.cid = int(cid)
        self.verify_hash = verify_hash


class TxMessage:
    def __init__(self, event: EventSubmitTransaction, verify: bool = False):
        self.event = event
        self.msg = None
        self.decoded = None
        self.signature = None
        self.verify = verify

    def __str__(self):
        return json.dumps(self.format_json(), indent=2)

    def format_json(self):
        return {
            "txUid": self.decoded.tx_uid(),
            "crossId": self.decoded.cross_id(),
            "cid": self.event.cid,
            "verifyHash": self.event.verify_hash,
            "blockNum": self.event.block_num,
            "blockHash": self.event.block_hash,
            "msg": "0x" + self.msg.hex(),
            "signature": "0x" + self.signature.hex(),
        }

    def check_msg(self, msg: bytes, to_sui: bool):
        try:
            self.decoded = Message(msg, to_sui)
            encode = self.decoded.encode()
        except Exception as e:
            logging.error(f"[BoolTxMessage] check_msg: msg={msg.hex()}, to_sui={to_sui}")

            raise e

        return encode

    def parse_storage_obj(self, storage_obj, to_sui: bool = False):
        msg = bytes(storage_obj["msg"])
        signature = bytearray(storage_obj["signature"])

        if not to_sui:
            signature[64] += 27

        checked_msg = self.check_msg(msg, to_sui)

        self.msg = checked_msg
        self.signature = bytes(signature)


def test_message():
    # {
    #     "to_sui": true,
    #     "txUniqueIdentification": "0x00066eed7257a51b00000000000000000000000000000000000000000000006d",
    #     "crossType": "0x966c63d14939ec9ace2dc744f5ea970e1cc6f20f12afefdcdff58ed5d321637e",
    #     "srcAnchor": "0x0000000000000000000000005700d38903da2d71fa2a912a3790c80b4a03e77a",
    #     "bnExtraFeed": "0x",
    #     "dstAnchor": "0x4a9158f9c54e568512d82c7756ed6a53faef0d06c9b63e08f0a79983b3fafdc9",
    #     "payload": "0x676f6f64",
    #     "origin": "0x6d00000000000000000000000000000000000000000000001ba55772ed6e060020966c63d14939ec9ace2dc744f5ea970e1cc6f20f12afefdcdff58ed5d321637e0000000000000000000000005700d38903da2d71fa2a912a3790c80b4a03e77a4a9158f9c54e568512d82c7756ed6a53faef0d06c9b63e08f0a79983b3fafdc90004676f6f64"
    # }
    msg = bytes.fromhex(
        "6d00000000000000000000000000000000000000000000001ba55772ed6e060020966c63d14939ec9ace2dc744f5ea970e1cc6f20f12afefdcdff58ed5d321637e0000000000000000000000005700d38903da2d71fa2a912a3790c80b4a03e77a4a9158f9c54e568512d82c7756ed6a53faef0d06c9b63e08f0a79983b3fafdc90004676f6f64"
    )

    decode_msg = Message(msg, True)
    assert decode_msg.encode() == msg
