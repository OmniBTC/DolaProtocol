from brownie import config, network

from dola_ethereum_sdk import DOLA_CONFIG, get_account, zero_address, set_ethereum_network


def deploy():
    account = get_account()
    cur_net = network.show_active()
    print(f"Current network:{cur_net}, account:{account}")
    wormhole_address = config["networks"][cur_net]["wormhole"]
    wormhole_chainid = config["networks"][cur_net]["wormhole_chainid"]

    print("deploy bridge pool...")
    bridge_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"].deploy(
        wormhole_address,
        wormhole_chainid,
        wormhole_chainid,
        1,
        zero_address(),
        {'from': account}
    )

    print("deploy test token btc...")
    btc = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].deploy("BTC", "BTC", {
                                                                   'from': account})

    print("deploy btc pool...")
    btc_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniPool"].deploy(0, wormhole_chainid,
                                                                       DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1].address, {'from': account})

    print("deploy test token usdt...")
    usdt = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].deploy(
        "USDT", "USDT", {'from': account})

    print("deploy usdt pool...")
    usdt_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniPool"].deploy(1, wormhole_chainid,
                                                                        DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1].address, {'from': account})

    print("deploy lending portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].deploy(DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address,
                                                                                  wormhole_chainid, {'from': account})

    print("----- deploy result -----")
    print(f"bridge_pool={bridge_pool}")
    print(f"btc={btc}")
    print(f"btc_pool={btc_pool}")
    print(f"usdt={usdt}")
    print(f"usdt_pool={usdt_pool}")
    print(f"lending_portal={lending_portal}")


if __name__ == "__main__":
    set_ethereum_network("bsc-test")
    deploy()
