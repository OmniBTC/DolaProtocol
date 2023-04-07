from brownie import Contract

from dola_ethereum_sdk import DOLA_CONFIG, config, network


def wormhole_adapter_pool_package():
    package_address = config["networks"][network.show_active()]["wormhole_adapter_pool"]
    return Contract.from_abi("WormholeAdapterPool", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"][-1].abi)


def lending_portal_package():
    package_address = config["networks"][network.show_active()]["lending_portal"]
    return Contract.from_abi("LendingPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"][-1].abi)


def system_portal_package():
    package_address = config["networks"][network.show_active()]["system_portal"]
    return Contract.from_abi("SystemPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"][-1].abi)


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1]
