from brownie import EncodeDecode, accounts
from pytest import fixture

POOL_DEPOSIT = 0
POOL_WITHDRAW = 1
POOL_SEND_MESSAGE = 2

SUPPLY = 0
WITHDRAW = 1
BORROW = 2
REPAY = 3
LIQUIDATE = 4
AS_COLLATERAL = 5
CANCEL_AS_COLLATERAL = 6


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

    # test pool codec
    # test encode and decode pool deposit payload
    pool_deposit_payload = encode_decode.encodeDepositPayload(
        [dola_chain_id, pool],
        [dola_chain_id, user],
        amount,
        app_id,
        app_payload
    )

    result = encode_decode.decodeDepositPayload(pool_deposit_payload)
    assert result == ((dola_chain_id, pool), (dola_chain_id,
                                              user), amount, app_id, POOL_DEPOSIT, f"0x{app_payload.hex()}")

    # test encode and decode pool withdraw payload
    pool_withdraw_payload = encode_decode.encodeWithdrawPayload(
        0,
        0,
        [dola_chain_id, pool],
        [dola_chain_id, user],
        amount,
    )
    result = encode_decode.decodeWithdrawPayload(
        pool_withdraw_payload)
    assert result == (0, 0, (dola_chain_id, pool), (dola_chain_id, user), amount, POOL_WITHDRAW)

    # test encode and decode pool send message payload
    send_message_payload = encode_decode.encodeSendMessagePayload(
        [dola_chain_id, user],
        app_id,
        app_payload
    )
    result = encode_decode.decodeSendMessagePayload(send_message_payload)
    assert result == ((dola_chain_id, user), app_id, POOL_SEND_MESSAGE, f"0x{app_payload.hex()}")

    # test lending codec
    # test encode and decode lending deposit payload
    lending_deposit_payload = encode_decode.encodeLendingDepositPayload(
        0,
        0,
        [dola_chain_id, user],
        0
    )
    result = encode_decode.decodeLendingDepositPayload(lending_deposit_payload)
    assert result == (0, 0, (dola_chain_id, user), 0)

    # test encode and decode lending withdraw payload
    lending_withdraw_payload = encode_decode.encodeLendingWithdrawPayload(
        dola_chain_id,
        0,
        amount,
        [dola_chain_id, pool],
        [dola_chain_id, user],
        1
    )
    result = encode_decode.decodeLendingWithdrawPayload(lending_withdraw_payload)
    assert result == (dola_chain_id, 0, amount, (dola_chain_id, pool), (dola_chain_id, user), 1)

    # test encode and decode lending liquidate payload
    lending_liquidate_payload = encode_decode.encodeLendingLiquidatePayload(
        dola_chain_id,
        0,
        [dola_chain_id, pool],
        0
    )
    result = encode_decode.decodeLendingLiquidatePayload(lending_liquidate_payload)
    assert result == (dola_chain_id, 0, (dola_chain_id, pool), 0, LIQUIDATE)

    # test encode and decode lending manage collateral payload
    lending_manage_collateral_payload = encode_decode.encodeManageCollateralPayload(
        [1, 2],
        5
    )
    result = encode_decode.decodeManageCollateralPayload(lending_manage_collateral_payload)
    assert result == ((1, 2), 5)

    # test system codec
    # test encode and decode system bind payload
    system_bind_payload = encode_decode.encodeBindPayload(
        dola_chain_id,
        0,
        [dola_chain_id, user],
        0
    )
    result = encode_decode.decodeBindPayload(system_bind_payload)
    assert result == (dola_chain_id, 0, (dola_chain_id, user), 0)
