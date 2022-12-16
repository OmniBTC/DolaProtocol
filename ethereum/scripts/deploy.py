from brownie import LendingPortal, OmniPool, BridgePool, MockToken

from scripts.helpful_scripts import get_account, get_wormhole, get_wormhole_chain_id, zero_address


def deploy():
    account = get_account()

    print("deploy bridge pool...")
    BridgePool.deploy(
        get_wormhole(),
        get_wormhole_chain_id(),
        get_wormhole_chain_id(),
        1,
        zero_address(),
        {'from': account}
    )

    print("deploy test token btc...")
    MockToken.deploy("BTC", "BTC", {'from': account})

    print("deploy btc pool...")
    OmniPool.deploy(0, get_wormhole_chain_id(),
                    BridgePool[-1].address, MockToken[-1].address, {'from': account})

    print("deploy test token usdt...")
    MockToken.deploy("USDT", "USDT", {'from': account})

    print("deploy usdt pool...")
    OmniPool.deploy(1, get_wormhole_chain_id(),
                    BridgePool[-1].address, MockToken[-1].address, {'from': account})

    print("deploy lending portal...")
    LendingPortal.deploy(BridgePool[-1].address,
                         get_wormhole_chain_id(), {'from': account})
