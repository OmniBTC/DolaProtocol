from dola_ethereum_sdk import DOLA_CONFIG


def omnipool_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniPool"]


def wormhole_bridge_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["BridgePool"]


def lending_portal_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"]


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"]
