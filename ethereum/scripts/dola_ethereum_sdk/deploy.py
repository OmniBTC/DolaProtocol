from brownie import config, network

from dola_ethereum_sdk import DOLA_CONFIG, get_account, zero_address, set_ethereum_network


def deploy():
    account = get_account()
    cur_net = network.show_active()
    print(f"Current network:{cur_net}, account:{account}")
    wormhole_address = config["networks"][cur_net]["wormhole"]
    wormhole_chainid = config["networks"][cur_net]["wormhole_chainid"]

    print("deploy  omnipool...")

    omnipool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniPool"].deploy(wormhole_chainid,
                                                                       account, {'from': account})

    print("deploy bridge pool...")
    bridge_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"].deploy(
        wormhole_address,
        wormhole_chainid,
        wormhole_chainid,
        1,
        zero_address(),
        omnipool.address,
        {'from': account}
    )

    omnipool.rely(bridge_pool.address, {'from': account})

    omnipool.deny(account, {'from': account})

    btc = deploy_token("BTC")

    usdt = deploy_token("USDT")

    usdc = deploy_token("USDC")

    print("deploy lending_core portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].deploy(
        DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address,
        wormhole_chainid, {'from': account})

    print("----- deploy result -----")
    print(f"bridge_pool:'{bridge_pool}'")
    print(f"omnipool:'{omnipool}'")
    print(f"btc:'{btc}'")
    print(f"usdt:'{usdt}'")
    print(f"usdc:'{usdc}'")
    print(f"lending_portal:'{lending_portal}'")


def deploy_token(token_name="USDT"):
    account = get_account()

    print(f"deploy test token {token_name}...")
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].deploy(
        token_name, token_name, {'from': account}
    )


if __name__ == "__main__":
    set_ethereum_network("polygon-zk-test")
    deploy()
