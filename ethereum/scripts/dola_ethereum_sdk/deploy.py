from brownie import config, network

from dola_ethereum_sdk import DOLA_CONFIG, get_account, set_ethereum_network


def deploy():
    account = get_account()
    cur_net = network.show_active()
    print(f"Current network:{cur_net}, account:{account}")
    wormhole_address = config["networks"][cur_net]["wormhole"]
    wormhole_chainid = config["networks"][cur_net]["wormhole_chainid"]

    print("deploy wormhole adapter pool...")
    wormhole_adapter_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"].deploy(
        wormhole_address,
        wormhole_chainid,
        0,
        {'from': account}
    )

    print("deploy dola pool...")

    dola_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["DolaPool"].deploy(
        wormhole_chainid,
        wormhole_adapter_pool.address,
        {'from': account}
    )

    print("deploy lending portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].deploy(
        wormhole_adapter_pool.address,
        {'from': account}
    )

    print("deploy system portal...")
    system_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"].deploy(
        wormhole_adapter_pool.address,
        {'from': account}
    )

    btc = deploy_token("BTC")

    usdt = deploy_token("USDT")

    usdc = deploy_token("USDC")

    print("----- deploy result -----")
    print(f"wormhole_adapter_pool:'{wormhole_adapter_pool}'")
    print(f"dola_pool:'{dola_pool}'")
    print(f"btc:'{btc}'")
    print(f"usdt:'{usdt}'")
    print(f"usdc:'{usdc}'")
    print(f"lending_portal:'{lending_portal}'")
    print(f"system_portal:'{system_portal}'")


def deploy_token(token_name="USDT"):
    account = get_account()

    print(f"deploy test token {token_name}...")
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].deploy(
        token_name, token_name, {'from': account}
    )


if __name__ == "__main__":
    set_ethereum_network("polygon-test")
    deploy()
