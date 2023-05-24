from brownie import WormholeAdapterPool, LendingPortal, MockToken, LibAsset, SystemPortal
from brownie import accounts
from pytest import fixture


@fixture
def wormhole_adapter_pool():
    LibAsset.deploy({'from': accounts[0]})
    return WormholeAdapterPool.deploy(accounts[0].address, 0, 0,
                                      1, "0xdef592d077e939fdf83f3a06cbd2b701d16d87fe255bfc834b851d70f062e95d",
                                      {'from': accounts[0]})


@fixture
def lending_portal(wormhole_adapter_pool):
    return LendingPortal.deploy(wormhole_adapter_pool.address, {'from': accounts[0]})


@fixture
def system_portal(wormhole_adapter_pool):
    return SystemPortal.deploy(wormhole_adapter_pool.address, {'from': accounts[0]})


@fixture
def usdc():
    return MockToken.deploy('USDC', 'USDC', {'from': accounts[0]})


def test_binding(system_portal):
    system_portal.binding(0, "0x29b710abd287961d02352a5e34ec5886c63aa5df87a209b2acbdd7c9282e6566", 0,
                          {'from': accounts[0], 'value': 0})


def test_deposit_withdraw(usdc, lending_portal, wormhole_adapter_pool):
    amount = 1e18
    usdc.mint(accounts[0].address, amount, {'from': accounts[0]})
    usdc.approve(lending_portal.address, amount, {'from': accounts[0]})
    lending_portal.supply(usdc.address, amount, 0, {'from': accounts[0]})

    eth = "0x0000000000000000000000000000000000000000"
    lending_portal.supply(eth, amount, 0, {'from': accounts[0], 'value': amount})
