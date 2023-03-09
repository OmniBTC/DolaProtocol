from dola_ethereum_sdk import DOLA_CONFIG


def omnipool_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SinglePool"][-1]


def wormhole_bridge_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1]


def lending_portal_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"][-1]


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1]
