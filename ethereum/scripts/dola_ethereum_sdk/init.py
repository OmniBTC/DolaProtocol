import os

import brownie
import requests
from brownie import (
    network,
    config, )

from dola_ethereum_sdk import load, get_account


def get_scan_api_key(net="polygon-test"):
    if "polygon-zk" in net:
        return os.getenv("POLYGON_ZK_API_KEY")
    elif "bsc" in net:
        return os.getenv("BSC_API_KEY")
    elif "polygon" in net:
        return os.getenv("POLYGON_API_KEY")


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
    bridge_pool = load.wormhole_adapter_pool_package()

    if nonce is None:
        nonce = bridge_pool.getNonce() - 1

    return str(bridge_pool.cachedVAA(nonce)), nonce


def lending_relay_event(net="polygon-test", start_block=0, end_block=99999999):
    lending_portal = load.lending_portal_package()
    topic = brownie.web3.keccak(text="RelayEvent(uint32,uint256)").hex()
    api_key = get_scan_api_key(net)
    params = {
        'module': 'logs',
        'action': 'getLogs',
        'address': str(lending_portal.address),
        'startblock': str(start_block),
        'endblock': str(end_block),
        'topic0': str(topic),
        'apikey': api_key
    }
    result = requests.get("https://api-testnet.polygonscan.com/api", params)

    return decode_relay_events(result.json())


def decode_relay_events(data):
    events = [d['data'] for d in data['result']]
    return {int(log[2:66], 16): int(log[66:], 16) for log in events}


def current_block_number():
    return brownie.web3.eth.block_number
