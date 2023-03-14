from dola_ethereum_sdk import DOLA_CONFIG


def wormhole_adapter_pool_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"][-1]


def lending_portal_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"][-1]


def system_portal_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"][-1]


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1]
