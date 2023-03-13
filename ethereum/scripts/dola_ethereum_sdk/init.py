from brownie import Contract
from brownie import (
    network,
    config,
)

from dola_ethereum_sdk import DOLA_CONFIG, load, get_account


def get_wormhole_chain_id():
    return config["networks"][network.show_active()]["wormhole_chainid"]


def get_wormhole():
    return config["networks"][network.show_active()]["wormhole"]


def usdt():
    return config["networks"][network.show_active()]["usdt"]


def btc():
    return config["networks"][network.show_active()]["btc"]


def usdc():
    return config["networks"][network.show_active()]["usdc"]


def eth():
    return "0x0000000000000000000000000000000000000000"


def register_owner(vaa):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package()
    omnipool.registerOwner(vaa, {'from': account})


def delete_owner(vaa):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package()
    omnipool.deleteOwner(vaa, {'from': account})


def register_spender(vaa):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package()
    omnipool.registerSpender(vaa, {'from': account})


def delete_spender(vaa):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package()
    omnipool.deleteSpender(vaa, {'from': account})


def bridge_pool_read_vaa(nonce=None):
    bridge_pool = Contract.from_abi(
        "WormholeAdapterPool", DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"][-1].address,
        DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"].abi)

    if nonce is None:
        nonce = bridge_pool.getNonce() - 1

    return str(bridge_pool.cachedVAA(nonce)), nonce
