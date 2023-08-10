import base64
from pathlib import Path

import requests
from brownie import config
from retrying import retry

import dola_ethereum_sdk
import dola_sui_sdk
from dola_ethereum_sdk import load as dola_ethereum_load, deploy as dola_ethereum_deploy, init as dola_ethereum_init
from dola_sui_sdk import init as dola_sui_init


@retry
def get_vaa_by_wormhole(tx_hash, emitter: str):
    wormhole_scan_url = dola_sui_sdk.sui_project.network_config['wormhole_scan_url']

    url = f"{wormhole_scan_url}vaas/21/{emitter}?pageSize=1"
    response = requests.get(url)

    data = response.json()['data'][0]
    if tx_hash != data['txHash']:
        return ""
    vaa_bytes = data['vaa']
    vaa = base64.b64decode(vaa_bytes).hex()
    return f"0x{vaa}"


def get_dola_contract(network, contract_address):
    return dola_ethereum_load.wormhole_adapter_pool_package(network, contract_address).getDolaContract()


def get_dola_chain_id():
    return dola_ethereum_init.get_dola_chain_id()


def get_wormhole_chain_id():
    return dola_ethereum_init.get_wormhole_chain_id()


def redeploy_evm_contract():
    return dola_ethereum_deploy.redeploy()


def create_register_new_spender_proposal(dola_chain_id, new_dola_contract):
    result = dola_sui_init.remote_register_spender(dola_chain_id, new_dola_contract)
    return result['effects']['transactionDigest']


def register_new_spender(vaa, old_wormhole_adapter_pool_address):
    dola_ethereum_init.register_spender(vaa, old_wormhole_adapter_pool_address)


def register_new_relayer(vaa, old_wormhole_adapter_pool_address):
    dola_ethereum_init.register_relayer(vaa, old_wormhole_adapter_pool_address)


def create_delete_old_spender_proposal(dola_chain_id, old_dola_contract):
    result = dola_sui_init.remote_delete_spender(dola_chain_id, old_dola_contract)
    return result['effects']['transactionDigest']


def delete_old_spender(vaa, new_wormhole_adapter_pool):
    dola_ethereum_init.delete_spender(vaa, new_wormhole_adapter_pool)


def remove_old_bridge(wormhole_emitter_chain):
    dola_sui_init.delete_remote_bridge(wormhole_emitter_chain)


def register_new_bridge(wormhole_emitter_chain, new_wormhole_adapter_pool):
    dola_sui_init.register_remote_bridge(wormhole_emitter_chain, new_wormhole_adapter_pool)


def get_core_emitter():
    core_emitter_list = dola_sui_init.get_wormhole_adapter_core_emitter()
    core_emitter = bytes(core_emitter_list).hex()
    return f'0x{core_emitter}'


def remote_add_relayer(dola_chain_id, relayer_address):
    result = dola_sui_init.remote_add_relayer(dola_chain_id, relayer_address)
    return result['effects']['transactionDigest']


def upgrade_evm_wormhole_adapter(network, old_version="v2"):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(network)

    old_wormhole_adapter_pool_address = config["networks"][network]["wormhole_adapter_pool"][old_version]
    old_wormhole_adapter_pool = dola_ethereum_load.wormhole_adapter_pool_package(
        network,
        config["networks"][network]["wormhole_adapter_pool"][old_version]
    )

    # 1. redeploy evm contract
    (wormhole_adapter_pool, lending_portal, system_portal) = redeploy_evm_contract()
    new_wormhole_adapter_pool_address = wormhole_adapter_pool.address

    # 2. register new remote spender
    dola_chain_id = get_dola_chain_id()
    new_dola_contract = get_dola_contract(network, new_wormhole_adapter_pool_address)
    tx_hash = create_register_new_spender_proposal(dola_chain_id, new_dola_contract)
    # wait for vaa
    while True:
        if vaa := get_vaa_by_wormhole(tx_hash, get_core_emitter()):
            register_new_spender(vaa, old_wormhole_adapter_pool_address)
            break

    # 3. remote add relayer
    relayer_address = "0x252CDE02Ec05bB96381FeC47DCc8C58c49499681"
    tx_hash = remote_add_relayer(dola_chain_id, relayer_address)
    # wait for vaa
    while True:
        if vaa := get_vaa_by_wormhole(tx_hash, get_core_emitter()):
            register_new_relayer(vaa, new_wormhole_adapter_pool_address)
            break

    # # 4. delete old bridge
    # wormhole_chain_id = get_wormhole_chain_id()
    # remove_old_bridge(wormhole_chain_id)
    #
    # # 5. register new bridge
    # register_new_bridge(wormhole_chain_id, new_wormhole_adapter_pool_address)
    #
    # # 6. delete old remote spender
    # new_dola_contract = get_dola_contract(network, new_wormhole_adapter_pool_address)
    # tx_hash = create_delete_old_spender_proposal(dola_chain_id, new_dola_contract)
    # # wait for vaa
    # while True:
    #     if vaa := get_vaa_by_wormhole(tx_hash, get_core_emitter()):
    #         delete_old_spender(vaa, old_wormhole_adapter_pool_address)
    #         break

    print(f"Successfully upgraded the evm contract for {network}.")
    print(f"Please update the following addresses in the ethereum/brownie-config.yaml for {network}:")
    print(f"  wormhole_adapter_pool: {new_wormhole_adapter_pool_address}")
    print(f"  lending_portal: {lending_portal.address}")
    print(f"  system_portal: {system_portal.address}")


if __name__ == '__main__':
    upgrade_evm_wormhole_adapter('polygon-main')
