from brownie import Contract

from dola_ethereum_sdk import DOLA_CONFIG, config


def womrhole_package(network):
    package_address = config["networks"][network]["wormhole"]
    return Contract.from_abi("IWormhole", package_address,
                             getattr(DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"].interface, "IWormhole").abi)


def wormhole_adapter_pool_package(network, package_address=None):
    if package_address is None:
        package_address = config["networks"][network]["wormhole_adapter_pool"]["latest"]
    return Contract.from_abi("WormholeAdapterPool", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"].abi)


def dola_pool_package(network, package_address=None):
    if package_address is None:
        package_address = config["networks"][network]["dola_pool"]
    return Contract.from_abi("DolaPool", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["DolaPool"].abi)


def lending_portal_package(network):
    package_address = config["networks"][network]["lending_portal"]
    return Contract.from_abi("LendingPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].abi)


def system_portal_package(network):
    package_address = config["networks"][network]["system_portal"]
    return Contract.from_abi("SystemPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"].abi)


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1]
