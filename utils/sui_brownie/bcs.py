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
        assert v0 <= MAX_U128
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


class Test(unittest.TestCase):
    def test_bool_true(self):
        in_value = True
        assert Bool(in_value).encode == b'\x01'

    def test_bool_false(self):
        in_value = False
        assert Bool(in_value).encode == b'\x00'

    def test_str(self):
        in_value = "1234567890"
        assert Identifier(in_value).encode == bytes([len(in_value)]) + b"1234567890"

    def test_u8(self):
        in_value = 1
        assert U8(in_value).encode == b"\x01"

    def test_u16(self):
        in_value = 11115
        assert U16(in_value).encode == b'k+'

    def test_u32(self):
        in_value = 1111111115

        assert U32(in_value).encode == b'\xcb5:B'

    def test_u64(self):
        in_value = 1111111111111111115

        assert U64(in_value).encode == b'\xcbq\xc4+\xabuk\x0f'

    def test_u128(self):
        in_value = 1111111111111111111111111111111111115

        assert U128(in_value).encode == b'\xcbq\x1c\xc7\x11\x06T\x8e4]\xdf\xde\x01\xfe\xd5\x00'

    def test_u256(self):
        in_value = 111111111111111111111111111111111111111111111111111111111111111111111111111115

        expect = b'\xcbq\x1c\xc7q\x1c\xc7q\x1c\x07\xea&\x97\xa57h\xb7\x05d\xa4Y\x10&R\x14*3n\x07\xa9\xa6\xf5'
        assert U256(in_value).encode == expect
