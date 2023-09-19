from __future__ import annotations
import logging
from nacl.signing import VerifyKey
from eth_utils import keccak
from eth_keys.datatypes import PublicKey, Signature
from typing import Union


def keccak_hash(msg: bytes):
    return keccak(msg)


class ED25519PublicKey:
    LENGTH: int = 32

    key: VerifyKey

    def __init__(self, key: Union[bytes, str]):
        if isinstance(key, bytes):
            self.key = VerifyKey(key)
        else:
            key_bytes = bytes.fromhex(key.replace("0x", ""))
            self.key = VerifyKey(key_bytes)

    def __str__(self) -> str:
        return f"0x{self.key.encode().hex()}"

    def hex(self):
        return str(self)

    def verify(self, data: bytes, signature: bytes) -> bool:
        try:
            self.key.verify(keccak_hash(data), signature)
        except Exception as e:
            logging.warning(f"[ED25519PublicKey] verify failed: {e}")
            return False
        return True


class ECDSAPublicKey:
    LENGTH: int = 65
    PREFIX: str = "0x04"

    key: PublicKey

    def __init__(self, key: Union[bytes, str]):
        if isinstance(key, bytes):
            self.key = PublicKey(key)
        else:
            key_bytes = bytes.fromhex(key.replace(self.PREFIX, "").replace("0x", ""))
            self.key = PublicKey(key_bytes)

    def __str__(self) -> str:
        return f"0x{self.key.to_compressed_bytes().hex()}"

    def hex(self):
        return str(self)

    def verify(self, data: bytes, signature: bytes) -> bool:
        assert signature[64] in [27, 28], "Invalid eth signature"

        try:
            _signature = bytearray(signature)
            _signature[64] -= 27

            _data = ethereum_signable_message(keccak_hash(data))

            self.key.verify_msg_hash(_data, Signature(_signature))
        except Exception as e:
            logging.warning(f"[ECDSAPublicKey] verify failed: {e}")
            return False
        return True


def ethereum_signable_message(msg: bytes):
    buffer = b"\x19Ethereum Signed Message:\n"
    msg_len = str(len(msg)).encode()

    buffer += msg_len
    buffer += msg

    return keccak_hash(buffer)


def test_ethereum_signable_message():
    msg = "123".encode()
    expect_hash = bytes.fromhex(
        "3b453794f074c43f21713fe98eaccb2728a71bd4584e5d5958e7e73546e02603"
    )

    assert expect_hash == ethereum_signable_message(msg)


def test_ecdsa_verify():
    # BoolWatcher(
    #     testnet_url,
    #     begin_height=6843506,
    #     max_block_range=20,
    #     filter_cids=[302, 303, 304],
    #     sui_cids=[302]
    # ).subscribe()
    msg = bytes.fromhex(
        "7257a51b000001a4000000000000000000000000000000000000000000000002966c63d14939ec9ace2dc744f5ea970e1cc6f20f12afefdcdff58ed5d321637e4a9158f9c54e568512d82c7756ed6a53faef0d06c9b63e08f0a79983b3fafdc900000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000993e87af195ac2ab570154f101ffe6463023dcb200000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000568656c6c6f000000000000000000000000000000000000000000000000000000"
    )
    signature = bytes.fromhex(
        "e0394229e79478dead3173459421dd690532d204c9747b882f1ff3612a77422a314d8724a16e25ba1b3c9989f13ffc9275b72bcd99047c481da1aabeaad515901b"
    )

    origin_key = "0x040214a5530d403a804b8bafafa84468716c5167038466330ea36a386ba27a9f611339e2c465d159c30b3777b356ee6abfa35d2b2856e4f75c7dd0d1ae575d8c21"

    pubkey = ECDSAPublicKey(origin_key)

    assert pubkey.verify(msg, signature)


def test_ed25519_verify():
    # BoolWatcher(
    #     testnet_url,
    #     begin_height=6414941,
    #     max_block_range=20,
    #     filter_cids=[302, 303, 304],
    #     sui_cids=[302]
    # ).subscribe()
    msg = bytes.fromhex(
        "6d00000000000000000000000000000000000000000000001ba55772ed6e060020966c63d14939ec9ace2dc744f5ea970e1cc6f20f12afefdcdff58ed5d321637e0000000000000000000000005700d38903da2d71fa2a912a3790c80b4a03e77a4a9158f9c54e568512d82c7756ed6a53faef0d06c9b63e08f0a79983b3fafdc90004676f6f64"
    )
    signature = bytes.fromhex(
        "07dca118b7b44dd142f6be41ce4bfc626175516bc833dcc0f99e4330de20178f5993b8611bbf1c2f4e043f3b28f22ee3824277f98a54c26713d5c2707834a703"
    )
    pubkey = ED25519PublicKey(
        "0x2d8d58b9cbbdcfaa8a730722b7aa22e7dc69c24c86f2cf2bd62c1f6a33d8db7f"
    )

    assert pubkey.verify(msg, signature)

    msg = bytes.fromhex(
        "6800000000000000000000000000000000000000000000001ba55772de05000020966c63d14939ec9ace2dc744f5ea970e1cc6f20f12afefdcdff58ed5d321637e000000000000000000000000b6b2e33305af7335b936decf0c5b6c53f24892cbbe8b88a09f3f14ebd6474cad34c75d75eebd89a253ec768ccb1f047fb980b485000568656c6c6f"
    )
    signature = bytes.fromhex(
        "b2e63ea16acfc1a1b4d5669aeeddc4e54b38e911c590816af2b05d2306d5f634bff5e767520848feb0d318e0404f386680621471ad2fc8768c30ad2c4b954909"
    )
    pubkey = ED25519PublicKey(
        "0x90671c9eb7ad7b1e62384a177e0d5cab1f53089d87bfb783bed543d89069e5f0"
    )

    assert pubkey.verify(msg, signature)


if __name__ == "__main__":
    test_ethereum_signable_message()
    test_ecdsa_verify()
    test_ed25519_verify()
