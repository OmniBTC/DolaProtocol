from brownie import EncodeDecode
from pytest import fixture

from scripts.helpful_scripts import get_account, padding_to_bytes


@fixture
def encode_decode():
    account = get_account()
    return EncodeDecode.deploy({'from': account})


def test_encode_decode(encode_decode):
    pool = padding_to_bytes("1", "left", 20)
    user = padding_to_bytes("2", "left", 20)
    amount = 1e8
    app_id = 0
    app_payload = b"test"
    dola_chain_id = 1
    pool_addr = encode_decode.encodeDolaAddress(dola_chain_id, pool)
    result = encode_decode.decodeDolaAddress(pool_addr)
    assert result == (dola_chain_id, pool)
    send_deposit_payload = encode_decode.encodeSendDepositPayload(
        [dola_chain_id, pool],
        [dola_chain_id, user],
        amount,
        app_id,
        app_payload
    )

    result = encode_decode.decodeSendDepositPayload(send_deposit_payload)
    assert result == ((dola_chain_id, pool), (dola_chain_id,
                      user), amount, app_id, f"0x{app_payload.hex()}")

    send_withdraw_payload = encode_decode.encodeSendWithdrawPayload(
        [dola_chain_id, pool],
        [dola_chain_id, user],
        app_id,
        app_payload
    )
    result = encode_decode.decodeSendWithdrawPayload(send_withdraw_payload)
    assert result == ((dola_chain_id, pool),
                      (dola_chain_id, user), app_id, f"0x{app_payload.hex()}")

    withdraw_pool = padding_to_bytes("3", "left", 20)
    send_deposit_withdraw_payload = encode_decode.encodeSendDepositAndWithdrawPayload(
        [dola_chain_id, pool],
        [dola_chain_id, user],
        amount,
        [dola_chain_id, withdraw_pool],
        app_id,
        app_payload
    )
    result = encode_decode.decodeSendDepositAndWithdrawPayload(
        send_deposit_withdraw_payload)
    assert result == ((dola_chain_id, pool), (dola_chain_id, user),
                      amount, (dola_chain_id, withdraw_pool), app_id, f"0x{app_payload.hex()}")
