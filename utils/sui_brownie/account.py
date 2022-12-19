# Copyright (c) Aptos
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import base64
import json
from typing import Union

from . import ed25519

INTENT_BYTES = [0, 0, 0]


class Account:
    """Represents an account as well as the private, public key-pair for the Aptos blockchain."""

    account_address: str
    private_key: ed25519.PrivateKey

    def __init__(
            self,
            mnemonic: str = None,
            private_key: Union[str, ed25519.PrivateKey] = None
    ):
        assert mnemonic is not None or private_key is not None
        self.mnemonic = mnemonic
        if mnemonic is not None:
            self.private_key: ed25519.PrivateKey = ed25519.PrivateKey.from_mnemonic(mnemonic)
        else:
            if isinstance(private_key, ed25519.PrivateKey):
                self.private_key: ed25519.PrivateKey = private_key
            else:
                self.private_key: ed25519.PrivateKey = ed25519.PrivateKey.from_hex(private_key)

    def __eq__(self, other: Account) -> bool:
        return (
                self.account_address == other.account_address
                and self.private_key == other.private_key
        )

    def sign(self, data: Union[bytes, str]):
        if isinstance(data, bytes):
            tx_bytes = list(data)
        else:
            tx_bytes = list(base64.b64decode(data))
        intent_message = []
        intent_message.extend(INTENT_BYTES)
        intent_message.extend(tx_bytes)
        return self.private_key.sign(bytes(intent_message))

    @property
    def account_address(self):
        return str(self.private_key.public_key().address())

    @staticmethod
    def generate() -> Account:
        private_key = ed25519.PrivateKey.random()
        return Account(private_key=private_key)

    @staticmethod
    def load_mnemonic(mnemonic: str) -> Account:
        return Account(mnemonic=mnemonic)

    @staticmethod
    def load_key(key: str) -> Account:
        return Account(private_key=key)

    @staticmethod
    def load(path: str) -> Account:
        with open(path) as file:
            data = json.load(file)
        return Account(private_key=data["private_key"])

    def store(self, path: str):
        data = {
            "account_address": self.account_address,
            "private_key": self.private_key.hex(),
        }
        with open(path, "w") as file:
            json.dump(data, file)

    def address(self) -> str:
        """Returns the address associated with the given account"""

        return self.account_address

    def public_key(self) -> ed25519.PublicKey:
        """Returns the public key for the associated account"""

        return self.private_key.public_key()

    def keystore(self) -> str:
        return self.private_key.generate_keystore()
