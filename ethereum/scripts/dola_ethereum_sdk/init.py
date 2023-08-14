import os
import time

import brownie
import requests
import web3
from brownie import (
    network,
    config, )
from web3_multi_provider import MultiProvider

from dola_ethereum_sdk import load, get_account, set_ethereum_network


def get_scan_api_key(net="polygon-test"):
    if "polygon-zk" in net:
        return os.getenv("POLYGON_ZK_API_KEY")
    elif "bsc" in net:
        return os.getenv("BSC_API_KEY")
    elif "arbitrum" in net:
        return os.getenv("ARBITRUM_API_KEY")
    elif "optimism" in net:
        return os.getenv("OPTIMISM_API_KEY")
    elif "polygon" in net:
        return os.getenv("POLYGON_API_KEY")


def get_wormhole_chain_id():
    return config["networks"][network.show_active()]["wormhole_chainid"]


def get_dola_chain_id():
    return config["networks"][network.show_active()]["dola_chain_id"]


def get_wormhole():
    return config["networks"][network.show_active()]["wormhole"]


def usdt():
    return config["networks"][network.show_active()]["tokens"]["USDT"]


def wbtc():
    return config["networks"][network.show_active()]["tokens"]["WBTC"]


def usdc():
    return config["networks"][network.show_active()]["tokens"]["USDC"]


def eth():
    return "0x0000000000000000000000000000000000000000"


def pools():
    return config["networks"][network.show_active()]["pools"]


def scan_rpc_url():
    return config["networks"][network.show_active()]["scan_rpc_url"]


def graphql_url(net):
    return config["networks"][net]["graphql_url"]


def web3_endpoints(net):
    return config["networks"][net]["endpoints"]


def register_spender(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.registerSpender(vaa, {'from': account})


def register_relayer(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.registerRelayer(vaa, {'from': account})


def delete_spender(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.deleteSpender(vaa, {'from': account})


def delete_relayer(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.removeRelayer(vaa, {'from': account})


def bridge_pool_read_vaa(nonce=None):
    bridge_pool = load.wormhole_adapter_pool_package()

    if nonce is None:
        nonce = bridge_pool.getNonce() - 1

    return str(bridge_pool.cachedVAA(nonce)), nonce


def get_gas_price(net):
    api_key = get_scan_api_key(net)

    base_url = scan_rpc_url()

    request_url = f'{base_url}?module=proxy&action=eth_gasPrice&apikey={api_key}'
    response = requests.get(request_url)

    return response.json()['result']


def decode_relay_events(response):
    events = []

    if response:
        for event in response['result']:
            block_number = int(event['blockNumber'], 16)
            tx_hash = event['transactionHash']
            timestamp = int(event['timeStamp'], 16)
            data = event['data']
            nonce = int(data[2:66], 16)
            sequence = int(data[66:130], 16)
            relay_fee = int(data[130:], 16)
            events.append({
                'blockNumber': block_number,
                'transactionHash': tx_hash,
                'nonce': nonce,
                'sequence': sequence,
                'amount': relay_fee,
                'blockTimestamp': timestamp,
            })

    return events


def query_relay_event_by_get_logs(w3_client, lending_portal: str, system_portal: str, start_block=0):
    log_filter = {'fromBlock': start_block, 'address': [lending_portal, system_portal],
                  'topics': ['0x5ed67fb05a814ff06302127070d306aa25929e34ac0e29ed7dfe3f0212854078']}

    logs = w3_client.eth.get_logs(log_filter)
    return decode_relay_logs(logs)


def decode_relay_logs(logs):
    events = []

    if logs:
        for log in logs:
            block_number = int(log['blockNumber'])
            tx_hash = log['transactionHash'].hex()
            timestamp = int(time.time())
            data = log['data']
            index = 2
            sequence = int(data[index:index + 64], 16)
            index += 64
            nonce = int(data[index:index + 64], 16)
            index += 64
            relay_fee = int(data[index:index + 64], 16)
            index += 64
            app_id = int(data[index:index + 64], 16)
            index += 64
            call_type = int(data[index:index + 64], 16)
            events.append({
                'blockNumber': block_number,
                'transactionHash': tx_hash,
                'nonce': nonce,
                'sequence': sequence,
                'feeAmount': relay_fee,
                'appId': app_id,
                'callType': call_type,
                'blockTimestamp': timestamp,
            })
    return events


def current_block_number():
    return brownie.web3.eth.block_number


def get_payload_from_chain(tx_id):
    tx = brownie.chain.get_transaction(tx_id)
    return tx.events['LogMessagePublished']['payload']


def get_dola_pool():
    return config["networks"][network.show_active()]["dola_pool"]


def get_dola_contract():
    network = brownie.network.show_active()
    wormhole_adapter = load.wormhole_adapter_pool_package(network)
    return wormhole_adapter.getDolaContract()


def get_all_spenders():
    dola_pool = load.dola_pool_package(brownie.network.show_active())
    all_spenders = []
    i = 0
    while True:
        try:
            result = dola_pool.allSpenders(i)
        except:
            break
        if str(result)[:2] != "0x":
            break
        all_spenders.append(result)
        i += 1
    return all_spenders


def multi_endpoints_web3(network, external_endpoint=None):
    if external_endpoint is None:
        external_endpoint = []

    endpoints = web3_endpoints(network) + external_endpoint
    return web3.Web3(MultiProvider(endpoints))


if __name__ == "__main__":
    net = "polygon-main"
    set_ethereum_network(net)
    lending_portal = load.lending_portal_package(net).address
    system_portal = load.system_portal_package(net).address
    external_endpoint = brownie.web3.provider.endpoint_uri
    w3_client = multi_endpoints_web3(net, [external_endpoint])

    account = get_account()
    erc20 = load.w3_erc20_package(w3_client.eth, usdc()['address'])
    balance = erc20.functions.balanceOf(account.address).call()
    print(balance)
    print(w3_client.eth.get_balance(account.address))
