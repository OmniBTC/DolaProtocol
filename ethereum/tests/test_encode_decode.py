from brownie import EncodeDecode, accounts
from pytest import fixture


def account():
    return accounts[0]


@fixture
def encode_decode():
    return EncodeDecode.deploy({'from': account()})


def test_encode_decode(encode_decode):
    pool = "0x" + "1".zfill(39)
    user = "0x" + "2".zfill(39)
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

    withdraw_pool = "0x" + "3".zfill(39)
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

    receive_withdraw_payload = encode_decode.encodeReceiveWithdrawPayload(
        0,
        0,
        [dola_chain_id, pool],
        [dola_chain_id, user],
        amount,
    )
    result = encode_decode.decodeReceiveWithdrawPayload(
        receive_withdraw_payload)
    assert result == (0, 0, (dola_chain_id, pool), (dola_chain_id, user), amount)
