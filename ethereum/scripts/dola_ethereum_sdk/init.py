import os
import urllib.parse

import brownie
import requests
from brownie import (
    network,
    config, )

from dola_ethereum_sdk import load, get_account, set_ethereum_network


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


def scan_rpc_url():
    return config["networks"][network.show_active()]["scan_rpc_url"]


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


def build_rpc_params(address, topic, api_key, start_block=0, end_block=99999999, limit=5):
    return {
        'module': 'logs',
        'action': 'getLogs',
        'address': str(address),
        'fromBlock': str(start_block),
        'toBlock': str(end_block),
        'topic0': str(topic),
        'page': '1',
        'offset': str(limit),
        'apikey': api_key
    }


def relay_events(start_block=0, end_block=99999999, limit=5):
    lending_portal = load.lending_portal_package()
    system_portal = load.system_portal_package()
    topic = brownie.web3.keccak(text="RelayEvent(uint64,uint256)").hex()
    net = network.show_active()
    api_key = get_scan_api_key(net)

    base_url = scan_rpc_url()

    system_rpc_params = build_rpc_params(system_portal.address, topic, api_key, start_block, end_block, limit)
    lending_rpc_params = build_rpc_params(lending_portal.address, topic, api_key, start_block, end_block, limit)
    headers = {}
    if "bsc" in net:
        headers = {
            'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
            'accept-language': 'zh,en;q=0.9,zh-CN;q=0.8',
            'cache-control': 'max-age=0',
            'cookie': '__stripe_mid=f0d7920d-dcf7-4f6c-926b-4381d16e2de09c7c5b; _gid=GA1.2.1608275934.1679541907; cf_clearance=qa.p7TdsepyFo0KzvZ2lfIlu1inGNy6mBSMfljWlBVw-1679544250-0-150; __cuid=d0e32142731a4b6a836bd4170892451f; __cf_bm=Nqn43kjTCFGnJA8hkEREgEj2cl_vIaM3KjGccp8RAn0-1679556064-0-AWqNjZOldwrmf77Zm4B3Pw7iAH+TVo4TviCd8flOviO0aA5EHI4nPZo/XAUveVRHAioAl+zD/71Dstoz0g1e/537mW5XHOAAy/9If5a2+n4i/qNnacDo4GScVC0StWNmiw==; amp_fef1e8=509f1beb-3ca0-426c-8a74-daa262842771R...1gs6ler9e.1gs6lfq49.v.7.16; _ga=GA1.1.327633374.1670917759; __stripe_sid=7331455c-b4fb-4f57-9aad-6507bfb2ab5ca17e57; _ga_PQY6J2Q8EP=GS1.1.1679556080.19.0.1679556090.0.0.0',
            'dnt': '1',
            'referer': 'https://docs.bscscan.com/v/bscscan-testnet/api-endpoints/logs',
            'sec-ch-ua': '"Not_A Brand";v="99", "Google Chrome";v="109", "Chromium";v="109"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Linux"',
            'sec-fetch-dest': 'document',
            'sec-fetch-mode': 'navigate',
            'sec-fetch-site': 'same-site',
            'sec-fetch-user': '?1',
            'upgrade-insecure-requests': '1',
            'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'
        }

    system_request_url = f"{base_url}?{urllib.parse.urlencode(system_rpc_params)}"

    system_relay_result = requests.get(
        system_request_url,
        headers=headers
    )

    lending_request_url = f"{base_url}?{urllib.parse.urlencode(lending_rpc_params)}"

    lending_relay_result = requests.get(
        lending_request_url,
        headers=headers
    )

    system_relay_events = decode_relay_events(system_relay_result.json())
    lending_relay_events = decode_relay_events(lending_relay_result.json())

    lending_relay_events.update(system_relay_events)

    return lending_relay_events


def decode_relay_events(data):
    events = [d['data'] for d in data['result']]
    return {int(log[2:66], 16): int(log[66:], 16) for log in events}


def current_block_number():
    return brownie.web3.eth.block_number


if __name__ == "__main__":
    set_ethereum_network("polygon-test")
    print(relay_events(start_block=33494168))
