from brownie import (
    network,
    config,
)
from brownie import Contract
from dola_ethereum_sdk import DOLA_CONFIG


def get_wormhole_chain_id():
    return config["networks"][network.show_active()]["wormhole_chainid"]


def get_wormhole():
    return config["networks"][network.show_active()]["wormhole"]


def usdt():
    return config["networks"][network.show_active()]["usdt"]


def btc():
    return config["networks"][network.show_active()]["btc"]


def usdt_pool():
    return config["networks"][network.show_active()]["usdt_pool"]


def btc_pool():
    return config["networks"][network.show_active()]["btc_pool"]


def get_pool_token(pool):
    omnipool = Contract.from_abi(
        "OmniPool", pool, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["OmniPool"].abi)
    return omnipool.token()


def bridge_pool_read_vaa():
    bridge_pool = Contract.from_abi(
        "MockBridgePool", DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"][-1].address, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockBridgePool"].abi)
    return (str(bridge_pool.getLatestVAA()), bridge_pool.getNonce())
