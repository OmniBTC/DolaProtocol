from brownie import MockBridgePool, OmniPool, MockToken, DolaPortal, EncodeDecode, accounts, config
from pytest import fixture

wormhole_address = config["networks"]["development"]["wormhole"]
wormhole_chainid = config["networks"]["development"]["wormhole_chainid"]


def account():
    return accounts[0]


def zero_address():
    return "0x0000000000000000000000000000000000000000"


@fixture
def encode_decode():
    return EncodeDecode.deploy({'from': account()})


@fixture
def omnipool():
    return OmniPool.deploy(wormhole_chainid,
                           account(), {'from': account()})


@fixture
def bridge_pool(omnipool):
    bridge = MockBridgePool.deploy(wormhole_address,
                                   wormhole_chainid,
                                   wormhole_chainid,
                                   1,
                                   zero_address(),
                                   omnipool.address,
                                   {'from': account()})
    omnipool.rely(bridge.address, {'from': account()})
    return bridge


@fixture
def usdt():
    return MockToken.deploy("USDT", "USDT", {'from': account()})


@fixture
def lending_portal(bridge_pool):
    return DolaPortal.deploy(bridge_pool.address,
                             wormhole_chainid, {'from': account()})


def test_supply(lending_portal, usdt, omnipool):
    amount = 1e18
    usdt.mint(account(), amount, {'from': account()})
    usdt.approve(omnipool.address, amount, {'from': account()})
    lending_portal.supply(usdt.address, amount, {'from': account()})
    assert omnipool.pools(usdt.address) == amount
    lending_portal.supply(zero_address(), amount, {
        'from': account(), 'value': amount})
    assert omnipool.pools(zero_address()) == amount


def test_withdraw(lending_portal, usdt, omnipool, bridge_pool, encode_decode):
    amount = 1e18

    usdt.mint(account(), amount, {'from': account()})
    usdt.approve(omnipool.address, amount, {'from': account()})
    lending_portal.supply(usdt.address, amount, {'from': account()})
    assert omnipool.pools(usdt.address) == amount
    receive_withdraw_payload = encode_decode.encodeReceiveWithdrawPayload(
        0, 0, [1, usdt.address], [1, account().address], 1e8, {'from': account()})
    bridge_pool.receiveWithdraw(receive_withdraw_payload, {'from': account()})
    assert omnipool.pools(usdt.address) == 0

    lending_portal.supply(zero_address(), amount, {
        'from': account(), 'value': amount})
    lending_portal.supply(zero_address(), amount, {
        'from': account(), 'value': amount})
    assert omnipool.pools(zero_address()) == 2 * amount

    account_balance = account().balance()

    receive_withdraw_payload = encode_decode.encodeReceiveWithdrawPayload(
        0, 0, [1, zero_address()], [1, account().address], 1e8, {'from': account()})
    bridge_pool.receiveWithdraw(receive_withdraw_payload, {'from': account()})
    assert omnipool.pools(zero_address()) == amount
    assert account().balance() == account_balance + amount
