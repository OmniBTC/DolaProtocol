# Copyright (c) Aptos
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import base64
import hashlib
import hmac

from mnemonic import Mnemonic

from typing import List

from nacl.signing import SigningKey, VerifyKey

from .utils import get_bytes, padding_to_bytes

DEFAULT_ED25519_DERIVATION_PATH = "m/44'/784'/0'/0'/0'"
ED25519_SEED = b"ed25519 seed"
HARDENED_OFFSET = 0x80000000


class PrivateKey:
    LENGTH: int = 32

    key: SigningKey

    def __init__(self, key: SigningKey):
        self.key = key

    def __eq__(self, other: PrivateKey):
        return self.key == other.key

    def __str__(self):
        return self.hex()

    @staticmethod
    def format_path(path: str) -> List[int]:
        result = []
        for k in path.split("/"):
            k = k.replace("'", "")
            try:
                result.append(int(k))
            except:
                pass
        return result

    @classmethod
    def from_mnemonic(cls, mnemonic: str, path=DEFAULT_ED25519_DERIVATION_PATH) -> PrivateKey:
        seed = Mnemonic.to_seed(mnemonic, passphrase="")
        mast_info = hmac.new(ED25519_SEED, get_bytes(seed), hashlib.sha512).digest()
        key = mast_info[:32]
        chain_code = mast_info[32:]
        for i in cls.format_path(path):
            index_buffer = bytes.fromhex(
                padding_to_bytes(str(hex(i + HARDENED_OFFSET)), "left", length=4)[2:])
            data = bytes([0]) + key + index_buffer
            info = hmac.new(chain_code, data, hashlib.sha512).digest()
            key = info[:32]
            chain_code = info[32:]
        return cls.from_hex(key.hex())

    @staticmethod
    def from_hex(value: str) -> PrivateKey:
        if value[0:2] == "0x":
            value = value[2:]
        return PrivateKey(SigningKey(bytes.fromhex(value)))

    def generate_keystore(self):
        """
        Support only ed25519
        :return: base64
        """
        data = ("00" + str(self)).replace("0x", "")
        return base64.b64encode(bytes.fromhex(data)).decode("ascii")

    def hex(self) -> str:
        return f"0x{self.key.encode().hex()}"

    def public_key(self) -> PublicKey:
        return PublicKey(self.key.verify_key)

    @staticmethod
    def random() -> PrivateKey:
        return PrivateKey(SigningKey.generate())

    def sign(self, data: bytes) -> Signature:
        return Signature(self.key.sign(data).signature)

    def base64(self):
        data = str(self)
        if data[:2] == "0x":
            data = data[2:]
        return base64.b64encode(bytes.fromhex(data)).decode("ascii")


class PublicKey:
    LENGTH: int = 32

    key: VerifyKey

    def __init__(self, key: VerifyKey):
        self.key = key

    def __eq__(self, other: PrivateKey):
        return self.key == other.key

    def __str__(self) -> str:
        return f"0x{self.key.encode().hex()}"

    def verify(self, data: bytes, signature: Signature) -> bool:
        try:
            self.key.verify(data, signature.data())
        except:
            return False
        return True

    def get_bytes(self) -> bytes:
        return self.key.encode()

    def base64(self):
        data = str(self)
        if data[:2] == "0x":
            data = data[2:]
        return base64.b64encode(bytes.fromhex(data)).decode("ascii")

    def address(self):
        data = bytes([0]) + get_bytes(str(self))
        hasher = hashlib.sha3_256()
        hasher.update(data)
        return "0x" + hasher.digest()[:20].hex()


class Signature:
    LENGTH: int = 64

    signature: bytes

    def __init__(self, signature: bytes):
        self.signature = signature

    def __eq__(self, other: Signature):
        return self.signature == other.signature

    def __str__(self) -> str:
        return f"0x{self.signature.hex()}"

    def data(self) -> bytes:
        return self.signature

    def get_bytes(self) -> bytes:
        return self.signature

    def base64(self):
        data = str(self)
        if data[:2] == "0x":
            data = data[2:]
        return base64.b64encode(bytes.fromhex(data)).decode("ascii")
