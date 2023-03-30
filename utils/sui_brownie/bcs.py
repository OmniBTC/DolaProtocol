# Copyright (c) OmniBTC
# SPDX-License-Identifier: GPL-3.0

from __future__ import annotations

import io
import typing
import unittest
from typing import Dict, List

MAX_U8 = 2 ** 8 - 1
MAX_U16 = 2 ** 16 - 1
MAX_U32 = 2 ** 32 - 1
MAX_U64 = 2 ** 64 - 1
MAX_U128 = 2 ** 128 - 1
MAX_U256 = 2 ** 256 - 1


def encode_list(data: list):
    return b"".join([v.encode for v in data])


class U8:
    def __init__(self, v0: int):
        assert v0 <= MAX_U8
        assert isinstance(v0, int)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        stream = io.BytesIO()
        stream.write(self.v0.to_bytes(1, "little", signed=False))
        return stream.getvalue()


class U16:
    def __init__(self, v0: int):
        assert v0 <= MAX_U16
        assert isinstance(v0, int)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        stream = io.BytesIO()
        stream.write(self.v0.to_bytes(2, "little", signed=False))
        return stream.getvalue()


class U32:
    def __init__(self, v0: int):
        assert v0 <= MAX_U32
        assert isinstance(v0, int)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        stream = io.BytesIO()
        stream.write(self.v0.to_bytes(4, "little", signed=False))
        return stream.getvalue()


class U64:
    def __init__(self, v0: int):
        assert v0 <= MAX_U64
        assert isinstance(v0, int)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        stream = io.BytesIO()
        stream.write(self.v0.to_bytes(8, "little", signed=False))
        return stream.getvalue()


class U128:
    def __init__(self, v0: int):
        assert v0 <= MAX_U8
        assert isinstance(v0, int)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        stream = io.BytesIO()
        stream.write(self.v0.to_bytes(16, "little", signed=False))
        return stream.getvalue()


class U256:
    def __init__(self, v0: int):
        assert v0 <= MAX_U256
        assert isinstance(v0, int)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        stream = io.BytesIO()
        stream.write(self.v0.to_bytes(32, "little", signed=False))
        return stream.getvalue()


class Bool:
    def __init__(self, v0: bool):
        assert isinstance(v0, bool)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        if self.v0:
            v0 = 1
        else:
            v0 = 0
        stream = io.BytesIO()
        stream.write(v0.to_bytes(1, "little", signed=False))
        return stream.getvalue()


class RustEnum:
    def __init__(self, key, value):
        assert isinstance(value, getattr(type(self), key)[0])
        self.key = key
        self.value = value

    @property
    def encode(self) -> bytes:
        (ty, index) = getattr(TransactionData, self.key)
        return bytes(index) + self.value.encode


class ObjectID:
    def __init__(self, v0):
        self.v0: SuiAddress = v0

    @property
    def encode(self) -> bytes:
        return self.v0.encode


class ObjectDigest:
    def __init__(self, v0):
        assert len(v0) == 32
        self.v0: List[U8] = v0

    @property
    def encode(self) -> bytes:
        return bytes([32]) + encode_list(self.v0)


SequenceNumber = U64
EpochId = U64


class SharedObject:
    def __init__(self, object_id, initial_shared_version, mutable):
        self.object_id: ObjectID = object_id
        self.initial_shared_version: SequenceNumber = initial_shared_version
        self.mutable: Bool = mutable


class ObjectRef:
    def __init__(self, object_id, sequence_number, object_digest):
        self.object_id: ObjectID = object_id
        self.sequence_number: SequenceNumber = sequence_number
        self.object_digest: ObjectDigest = object_digest

    @property
    def encode(self) -> bytes:
        return self.object_id.encode + self.sequence_number.encode + self.object_digest.encode


class ObjectArg:
    ImmOrOwnedObject = (ObjectRef, 0)
    SharedObject = (SharedObject, 1)

    def __init__(self, key, value):
        assert isinstance(value, getattr(TransactionData, key)[0])
        self.key = key
        self.value = value

    @property
    def encode(self) -> bytes:
        (ty, index) = getattr(TransactionData, self.key)
        return bytes(index) + self.value.encode


class Pure:
    def __init__(self, v0):
        self.v0: List[U8] = v0

    @property
    def encode(self) -> bytes:
        return encode_list(self.v0)


class CallArg(RustEnum):
    Pure = (Pure, 0)
    Object = (ObjectArg, 1)


class Identifier:
    def __init__(self, v0):
        assert isinstance(v0, str)
        self.v0 = v0

    @property
    def encode(self) -> bytes:
        return bytes([len(self.v0)]) + bytes(self.v0, encoding="ascii")


class NONE:
    @property
    def encode(self) -> bytes:
        return bytes("")


class StructTag:
    def __init__(self,
                 address: SuiAddress,
                 module: Identifier,
                 name: Identifier,
                 type_params: List[TypeTag],
                 ):
        self.address: SuiAddress = address
        self.module: Identifier = module
        self.name: Identifier = name
        self.type_params: List[TypeTag] = type_params

    @property
    def encode(self) -> bytes:
        return self.address.encode + self.module.encode + self.name.encode + encode_list(self.type_params)


class TypeTag(RustEnum):
    Bool = (NONE, 0)
    U8 = (NONE, 1)
    U64 = (NONE, 2)
    U128 = (NONE, 3)
    Address = (NONE, 4)
    Signer = (NONE, 5)
    Vector = (RustEnum, 6),
    Struct = (StructTag, 7),
    U16 = (NONE, 8)
    U32 = (NONE, 9)
    U256 = (NONE, 10)


class ProgrammableMoveCall:
    def __init__(self,
                 package: ObjectID,
                 module: Identifier,
                 function: Identifier,
                 type_arguments: List[TypeTag],
                 arguments: List[Argument]
                 ):
        self.package = package
        self.module = module
        self.function = function
        self.type_arguments = type_arguments
        self.arguments = arguments

    @property
    def encode(self) -> bytes:
        return self.package.encode + self.module.encode + \
               self.function.encode + encode_list(self.type_arguments) + encode_list(self.arguments)


class NestedResult:
    def __init__(self, v0, v1):
        self.v0: U16 = v0
        self.v1: U16 = v1

    @property
    def encode(self) -> bytes:
        return self.v0.encode + self.v1.encode


class Argument(RustEnum):
    GasCoin = (NONE, 0)
    Input = (U16, 1)
    Result = (U16, 2)
    NestedResult = (NestedResult, 3)


class TransferObjects:
    def __init__(self, v0, v1):
        self.v0: List[Argument] = v0
        self.v1: Argument = v1

    @property
    def encode(self) -> bytes:
        return encode_list(self.v0) + self.v1.encode


class SplitCoins:
    def __init__(self, v0, v1):
        self.v0: Argument = v0
        self.v1: List[Argument] = v1

    @property
    def encode(self) -> bytes:
        return self.v0.encode + encode_list(self.v1)


class MergeCoins:
    def __init__(self, v0, v1):
        self.v0: Argument = v0
        self.v1: List[Argument] = v1

    @property
    def encode(self) -> bytes:
        return self.v0.encode + encode_list(self.v1)


class Publish:
    def __init__(self, v0, v1):
        self.v0: List[List[U8]] = v0
        self.v1: List[ObjectID] = v1

    @property
    def encode(self) -> bytes:
        return encode_list(self.v0) + encode_list(self.v1)


class OptionTypeTag(RustEnum):
    NONE = (NONE, 0)
    Some = (TypeTag, 1)


class MakeMoveVec:
    def __init__(self, v0, v1):
        self.v0: OptionTypeTag = v0
        self.v1: List[Argument] = v1

    @property
    def encode(self) -> bytes:
        return self.v0.encode + encode_list(self.v1)


class Upgrade:
    def __init__(self, v0, v1, v2, v3):
        self.v0: List[List[U8]] = v0
        self.v1: List[ObjectID] = v1
        self.v2: ObjectID = v2
        self.v3: Argument = v3

    @property
    def encode(self) -> bytes:
        return encode_list(self.v0) + encode_list(self.v1) + self.v2.encode + self.v3.encode


class Command(RustEnum):
    MoveCall = (ProgrammableMoveCall, 0)
    TransferObjects = (TransferObjects, 1)
    SplitCoins = (SplitCoins, 2)
    MergeCoins = (MergeCoins, 3)
    Publish = (Publish, 4)
    MakeMoveVec = (MakeMoveVec, 5)
    Upgrade = (Upgrade, 6)


class ProgrammableTransaction:
    def __init__(self, inputs, commands):
        self.inputs: List[CallArg] = inputs
        self.commands: List[Command] = commands

    @property
    def encode(self) -> bytes:
        return encode_list(self.inputs) + encode_list(self.commands)


class TransactionExpiration(RustEnum):
    NONE = (NONE, 0)
    Epoch = (EpochId, 1)


class GasData:
    def __init__(self, payment, owner, price, budget):
        self.payment: List[ObjectRef] = payment
        self.owner: SuiAddress = owner
        self.price: U64 = price
        self.budget: U64 = budget

    @property
    def encode(self) -> bytes:
        return encode_list(self.payment) + self.owner.encode + self.price.encode + self.budget.encode


class SuiAddress:
    def __init__(self, v0):
        assert len(v0) == 32
        self.v0: List[U8] = v0

    @property
    def encode(self) -> bytes:
        return encode_list(self.v0)


class TransactionKind(RustEnum):
    ProgrammableTransaction = (ProgrammableTransaction, 0)


class TransactionDataV1:
    def __init__(
            self,
            kind,
            sender,
            gas_data,
            expiration
    ):
        self.kind: TransactionKind = kind
        self.sender: SuiAddress = sender
        self.gas_data: GasData = gas_data
        self.expiration: TransactionExpiration = expiration

    @property
    def encode(self):
        return self.kind.encode + self.sender.encode + self.gas_data.encode + self.expiration.encode


class TransactionData(RustEnum):
    V1 = (TransactionDataV1, 0)


class Deserializer:
    _input: io.BytesIO
    _length: int

    def __init__(self, data: bytes):
        self._length = len(data)
        self._input = io.BytesIO(data)

    def remaining(self) -> int:
        return self._length - self._input.tell()

    def bool(self) -> bool:
        value = int.from_bytes(self._read(1), byteorder="little", signed=False)
        if value == 0:
            return False
        elif value == 1:
            return True
        else:
            raise Exception("Unexpected boolean value: ", value)

    def to_bytes(self) -> bytes:
        return self._read(self.uleb128())

    def fixed_bytes(self, length: int) -> bytes:
        return self._read(length)

    def map(
            self,
            key_decoder: typing.Callable[[Deserializer], typing.Any],
            value_decoder: typing.Callable[[Deserializer], typing.Any],
    ) -> Dict[typing.Any, typing.Any]:
        length = self.uleb128()
        values: Dict = {}
        while len(values) < length:
            key = key_decoder(self)
            value = value_decoder(self)
            values[key] = value
        return values

    def sequence(
            self,
            value_decoder: typing.Callable[[Deserializer], typing.Any],
    ) -> List[typing.Any]:
        length = self.uleb128()
        values: List = []
        while len(values) < length:
            values.append(value_decoder(self))
        return values

    def str(self) -> str:
        return self.to_bytes().decode()

    def struct(self, struct: typing.Any) -> typing.Any:
        return struct.deserialize(self)

    def u8(self) -> int:
        return self._read_int(1)

    def u16(self) -> int:
        return self._read_int(2)

    def u32(self) -> int:
        return self._read_int(4)

    def u64(self) -> int:
        return self._read_int(8)

    def u128(self) -> int:
        return self._read_int(16)

    def u256(self) -> int:
        return self._read_int(32)

    def uleb128(self) -> int:
        value = 0
        shift = 0

        while value <= MAX_U32:
            byte = self._read_int(1)
            value |= (byte & 0x7F) << shift
            if byte & 0x80 == 0:
                break
            shift += 7

        if value > MAX_U128:
            raise Exception("Unexpectedly large uleb128 value")

        return value

    def _read(self, length: int) -> bytes:
        value = self._input.read(length)
        if value is None or len(value) < length:
            actual_length = 0 if value is None else len(value)
            error = (
                f"Unexpected end of input. Requested: {length}, found: {actual_length}"
            )
            raise Exception(error)
        return value

    def _read_int(self, length: int) -> int:
        return int.from_bytes(self._read(length), byteorder="little", signed=False)


class Serializer:
    _output: io.BytesIO

    def __init__(self):
        self._output = io.BytesIO()

    def output(self) -> bytes:
        return self._output.getvalue()

    def bool(self, value: bool):
        self._write_int(int(value), 1)

    def to_bytes(self, value: bytes):
        self.uleb128(len(value))
        self._output.write(value)

    def fixed_bytes(self, value):
        self._output.write(value)

    def map(
            self,
            values: typing.Dict[typing.Any, typing.Any],
            key_encoder: typing.Callable[[Serializer, typing.Any], bytes],
            value_encoder: typing.Callable[[Serializer, typing.Any], bytes],
    ):
        encoded_values = []
        for (key, value) in values.items():
            encoded_values.append(
                (encoder(key, key_encoder), encoder(value, value_encoder))
            )
        encoded_values.sort(key=lambda item: item[0])

        self.uleb128(len(encoded_values))
        for (key, value) in encoded_values:
            self.fixed_bytes(key)
            self.fixed_bytes(value)

    @staticmethod
    def sequence_serializer(
            value_encoder: typing.Callable[[Serializer, typing.Any], bytes],
    ):
        return lambda self, values: self.sequence(values, value_encoder)

    def sequence(
            self,
            values: typing.List[typing.Any],
            value_encoder: typing.Callable[[Serializer, typing.Any], bytes],
    ):
        self.uleb128(len(values))
        for value in values:
            self.fixed_bytes(encoder(value, value_encoder))

    def str(self, value: str):
        self.to_bytes(value.encode())

    def struct(self, value: typing.Any):
        value.serialize(self)

    def u8(self, value: int):
        if value > MAX_U8:
            raise Exception(f"Cannot encode {value} into u8")

        self._write_int(value, 1)

    def u16(self, value: int):
        if value > MAX_U16:
            raise Exception(f"Cannot encode {value} into u16")

        self._write_int(value, 2)

    def u32(self, value: int):
        if value > MAX_U32:
            raise Exception(f"Cannot encode {value} into u32")

        self._write_int(value, 4)

    def u64(self, value: int):
        if value > MAX_U64:
            raise Exception(f"Cannot encode {value} into u64")

        self._write_int(value, 8)

    def u128(self, value: int):
        if value > MAX_U128:
            raise Exception(f"Cannot encode {value} into u128")

        self._write_int(value, 16)

    def u256(self, value: int):
        if value > MAX_U256:
            raise Exception(f"Cannot encode {value} into u256")

        self._write_int(value, 32)

    def uleb128(self, value: int):
        if value > MAX_U32:
            raise Exception(f"Cannot encode {value} into uleb128")

        while value >= 0x80:
            # Write 7 (lowest) bits of data and set the 8th bit to 1.
            byte = value & 0x7F
            self.u8(byte | 0x80)
            value >>= 7

        # Write the remaining bits of data and set the highest bit to 0.
        self.u8(value & 0x7F)

    def _write_int(self, value: int, length: int):
        self._output.write(value.to_bytes(length, "little", signed=False))


def encoder(
        value: typing.Any, encoder: typing.Callable[[Serializer, typing.Any], typing.Any]
) -> bytes:
    ser = Serializer()
    encoder(ser, value)
    return ser.output()


class Test(unittest.TestCase):
    def test_bool_true(self):
        in_value = True

        ser = Serializer()
        ser.bool(in_value)
        print(ser.output())
        der = Deserializer(ser.output())
        out_value = der.bool()

        self.assertEqual(in_value, out_value)

    def test_bool_false(self):
        in_value = False

        ser = Serializer()
        ser.bool(in_value)
        print(ser.output())
        der = Deserializer(ser.output())
        out_value = der.bool()

        self.assertEqual(in_value, out_value)

    def test_bool_error(self):
        ser = Serializer()
        ser.u8(32)
        der = Deserializer(ser.output())
        with self.assertRaises(Exception):
            der.bool()

    def test_bytes(self):
        in_value = b"1234567890"

        ser = Serializer()
        ser.to_bytes(in_value)
        der = Deserializer(ser.output())
        out_value = der.to_bytes()

        self.assertEqual(in_value, out_value)

    def test_map(self):
        in_value = {"a": 12345, "b": 99234, "c": 23829}

        ser = Serializer()
        ser.map(in_value, Serializer.str, Serializer.u32)
        der = Deserializer(ser.output())
        out_value = der.map(Deserializer.str, Deserializer.u32)

        self.assertEqual(in_value, out_value)

    def test_sequence(self):
        in_value = ["a", "abc", "def", "ghi"]

        ser = Serializer()
        ser.sequence(in_value, Serializer.str)
        der = Deserializer(ser.output())
        out_value = der.sequence(Deserializer.str)

        self.assertEqual(in_value, out_value)

    def test_sequence_serializer(self):
        in_value = ["a", "abc", "def", "ghi"]

        ser = Serializer()
        seq_ser = Serializer.sequence_serializer(Serializer.str)
        seq_ser(ser, in_value)
        der = Deserializer(ser.output())
        out_value = der.sequence(Deserializer.str)

        self.assertEqual(in_value, out_value)

    def test_str(self):
        in_value = "1234567890"

        ser = Serializer()
        ser.str(in_value)
        der = Deserializer(ser.output())
        out_value = der.str()

        self.assertEqual(in_value, out_value)

    def test_u8(self):
        in_value = 1

        ser = Serializer()
        ser.u8(in_value)
        print(ser.output())
        der = Deserializer(ser.output())
        out_value = der.u8()

        self.assertEqual(in_value, out_value)

    def test_u16(self):
        in_value = 11115

        ser = Serializer()
        ser.u16(in_value)
        der = Deserializer(ser.output())
        out_value = der.u16()

        self.assertEqual(in_value, out_value)

    def test_u32(self):
        in_value = 1111111115

        ser = Serializer()
        ser.u32(in_value)
        der = Deserializer(ser.output())
        out_value = der.u32()

        self.assertEqual(in_value, out_value)

    def test_u64(self):
        in_value = 1111111111111111115

        ser = Serializer()
        ser.u64(in_value)
        der = Deserializer(ser.output())
        out_value = der.u64()

        self.assertEqual(in_value, out_value)

    def test_u128(self):
        in_value = 1111111111111111111111111111111111115

        ser = Serializer()
        ser.u128(in_value)
        der = Deserializer(ser.output())
        out_value = der.u128()

        self.assertEqual(in_value, out_value)

    def test_u256(self):
        in_value = 111111111111111111111111111111111111111111111111111111111111111111111111111115

        ser = Serializer()
        ser.u256(in_value)
        der = Deserializer(ser.output())
        out_value = der.u256()

        self.assertEqual(in_value, out_value)

    def test_uleb128(self):
        in_value = 1111111115

        ser = Serializer()
        ser.uleb128(in_value)
        der = Deserializer(ser.output())
        out_value = der.uleb128()

        self.assertEqual(in_value, out_value)


if __name__ == "__main__":
    unittest.main()
