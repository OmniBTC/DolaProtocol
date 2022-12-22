from brownie import LendingPortal, OmniPool, BridgePool, MockToken

from scripts.init import get_account, get_wormhole, get_wormhole_chain_id, zero_address


def deploy():
    account = get_account()

    print("deploy bridge pool...")
    bridge_pool = BridgePool.deploy(
        get_wormhole(),
        get_wormhole_chain_id(),
        get_wormhole_chain_id(),
        1,
        zero_address(),
        {'from': account}
    )

    print("deploy test token btc...")
    btc = MockToken.deploy("BTC", "BTC", {'from': account})

    print("deploy btc pool...")
    btc_pool = OmniPool.deploy(0, get_wormhole_chain_id(),
                               BridgePool[-1].address, MockToken[-1].address, {'from': account})

    print("deploy test token usdt...")
    usdt = MockToken.deploy("USDT", "USDT", {'from': account})

    print("deploy usdt pool...")
    usdt_pool = OmniPool.deploy(1, get_wormhole_chain_id(),
                                BridgePool[-1].address, MockToken[-1].address, {'from': account})

    print("deploy lending portal...")
    lending_portal = LendingPortal.deploy(BridgePool[-1].address,
                                          get_wormhole_chain_id(), {'from': account})

    print("----- deploy result -----")
    print(f"bridge_pool={bridge_pool}")
    print(f"btc={btc}")
    print(f"btc_pool={btc_pool}")
    print(f"usdt={usdt}")
    print(f"usdt_pool={usdt_pool}")
    print(f"lending_portal={lending_portal}")
