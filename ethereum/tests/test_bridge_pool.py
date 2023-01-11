from brownie import MockBridgePool, OmniPool, OmniETHPool, MockToken, LendingPortal, EncodeDecode, PoolOwner, accounts, config
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
def bridge_pool():
    return MockBridgePool.deploy(wormhole_address,
                                 wormhole_chainid,
                                 wormhole_chainid,
                                 1,
                                 zero_address(),
                                 {'from': account()})


@fixture
def usdt():
    return MockToken.deploy("USDT", "USDT", {'from': account()})


@fixture
def pool_owner(bridge_pool):
    pool_owner = PoolOwner.deploy(bridge_pool, {'from': account()})
    bridge_pool.initPool(pool_owner.address, {'from': account()})
    return pool_owner


@fixture
def usdt_pool(usdt, pool_owner):
    return OmniPool.deploy(wormhole_chainid,
                           pool_owner.address, usdt.address, {'from': account()})


@fixture
def eth_pool(pool_owner):
    return OmniETHPool.deploy(wormhole_chainid,
                              pool_owner.address, {'from': account()})


@fixture
def lending_portal(bridge_pool):
    return LendingPortal.deploy(bridge_pool.address,
                                wormhole_chainid, {'from': account()})


def test_supply(lending_portal, usdt, usdt_pool, eth_pool):
    amount = 1e18
    usdt.mint(account(), amount, {'from': account()})
    usdt.approve(usdt_pool.address, amount, {'from': account()})
    lending_portal.supply(usdt_pool.address, amount, {'from': account()})
    assert usdt_pool.balance() == amount
    lending_portal.supply(eth_pool.address, amount, {
                          'from': account(), 'value': amount})
    assert eth_pool.balance() == amount


def test_withdraw(lending_portal, usdt, usdt_pool, eth_pool, bridge_pool, encode_decode):
    amount = 1e18

    usdt.mint(account(), amount, {'from': account()})
    usdt.approve(usdt_pool.address, amount, {'from': account()})
    lending_portal.supply(usdt_pool.address, amount, {'from': account()})
    assert usdt_pool.balance() == amount
    receive_withdraw_payload = encode_decode.encodeReceiveWithdrawPayload(
        [1, usdt_pool.address], [1, account().address], 1e8, {'from': account()})
    bridge_pool.receiveWithdraw(receive_withdraw_payload, {'from': account()})
    assert usdt_pool.balance() == 0

    lending_portal.supply(eth_pool.address, amount, {
                          'from': account(), 'value': amount})
    lending_portal.supply(eth_pool.address, amount, {
                          'from': account(), 'value': amount})
    assert eth_pool.balance() == 2 * amount

    account_balance = account().balance()

    receive_withdraw_payload = encode_decode.encodeReceiveWithdrawPayload(
        [1, eth_pool.address], [1, account().address], 1e8, {'from': account()})
    bridge_pool.receiveWithdraw(receive_withdraw_payload, {'from': account()})
    assert eth_pool.balance() == amount
    assert account().balance() == account_balance + amount
