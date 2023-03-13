from brownie import MockWormholeAdapterPool, LendingPortal, MockToken, LibAsset
from brownie import accounts
from pytest import fixture


@fixture
def wormhole_adapter_pool():
    LibAsset.deploy({'from': accounts[0]})
    return MockWormholeAdapterPool.deploy(accounts[0].address, 0, 0, {'from': accounts[0]})


@fixture
def lending_portal(wormhole_adapter_pool):
    return LendingPortal.deploy(wormhole_adapter_pool.address, {'from': accounts[0]})


@fixture
def usdc():
    return MockToken.deploy('USDC', 'USDC', {'from': accounts[0]})


def test_deposit_withdraw(usdc, lending_portal):
    amount = 1e18
    usdc.mint(accounts[0].address, amount, {'from': accounts[0]})
    usdc.approve(lending_portal.address, amount, {'from': accounts[0]})
    lending_portal.supply(usdc.address, amount, {'from': accounts[0]})

    eth = "0x0000000000000000000000000000000000000000"
    lending_portal.supply(eth, amount, {'from': accounts[0], 'value': amount})
