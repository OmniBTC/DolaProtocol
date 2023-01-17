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

    eth_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniETHPool"].deploy(wormhole_chainid,
                                                                          DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address, {'from': account})

    (btc, btc_pool) = deploy_pool("BTC")

    (usdt, usdt_pool) = deploy_pool("USDT")

    (usdc, usdc_pool) = deploy_pool("USDC")

    print("deploy lending portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].deploy(DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address,
                                                                                  wormhole_chainid, {'from': account})

    print("----- deploy result -----")
    print(f"bridge_pool:'{bridge_pool}'")
    print(f"eth_pool:'{eth_pool}'")
    print(f"btc:'{btc}'")
    print(f"btc_pool:'{btc_pool}'")
    print(f"usdt:'{usdt}'")
    print(f"usdt_pool:'{usdt_pool}'")
    print(f"usdc:'{usdc}'")
    print(f"usdc_pool:'{usdc_pool}'")
    print(f"lending_portal:'{lending_portal}'")


def deploy_pool(token_name="USDT"):
    account = get_account()
    cur_net = network.show_active()
    wormhole_chainid = config["networks"][cur_net]["wormhole_chainid"]

    print(f"deploy test token {token_name}...")
    token = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].deploy(token_name, token_name, {
        'from': account})

    print(f"deploy {token_name} pool...")
    token_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniPool"].deploy(wormhole_chainid,
                                                                         DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1].address, {'from': account})

    return (token, token_pool)


if __name__ == "__main__":
    set_ethereum_network("polygon-zk-test")
    deploy()
