# dola protocol monitor
import brownie
import config
import dola_ethereum_sdk
import dola_sui_sdk
import functools
import logging
import queue
import time
from dola_ethereum_sdk import load as dola_ethereum_load, init as dola_ethereum_init
from dola_sui_sdk import load as dola_sui_load, sui_project, interfaces
from multiprocessing import Manager
from pathlib import Path
from sui_brownie.parallelism import ProcessExecutor


def parse_u256(data: list):
    output = 0
    for i in range(32):
        output = (output << 8) + int(data[31 - i])
    return output


def convert_dola_decimal(amount: int, decimal: int):
    if decimal < config.DOLA_DECIMAL:
        return amount * 10 ** (config.DOLA_DECIMAL - decimal)
    else:
        return amount // 10 ** (decimal - config.DOLA_DECIMAL)


def get_otoken_total_supply(dola_pool_id):
    dola_protocol = dola_sui_load.dola_protocol_package()

    lending_storage = sui_project.network_config['objects']['LendingStorage']

    result = dola_protocol.lending_logic.total_otoken_supply.inspect(
        lending_storage,
        dola_pool_id
    )

    return parse_u256(result['results'][0]['returnValues'][0][0])


def get_dtoken_total_supply(dola_pool_id):
    dola_protocol = dola_sui_load.dola_protocol_package()

    lending_storage = sui_project.network_config['objects']['LendingStorage']

    result = dola_protocol.lending_logic.total_dtoken_supply.inspect(
        lending_storage,
        dola_pool_id
    )

    return parse_u256(result['results'][0]['returnValues'][0][0])


def get_sui_pool_balance(pool_address):
    result = sui_project.client.sui_getObject(pool_address, {"showContent": True})
    fields = result['data']['content']['fields']
    balance = int(fields['balance'])
    decimal = int(fields['decimal'])

    return convert_dola_decimal(balance, decimal)


def get_erc20_balance(dola_pool, token):
    erc20 = dola_ethereum_load.erc20_package(token)
    decimal = erc20.decimals()
    balance = erc20.balanceOf(dola_pool)

    return convert_dola_decimal(balance, decimal)


def get_w3_erc20_balance(w3_eth, dola_pool, token):
    token = brownie.web3.toChecksumAddress(token)
    erc20 = dola_ethereum_load.w3_erc20_package(w3_eth, token)
    decimal = erc20.functions.decimals().call()
    balance = erc20.functions.balanceOf(dola_pool).call()

    return convert_dola_decimal(balance, decimal)


def get_eth_balance(dola_pool):
    balance = brownie.web3.eth.get_balance(dola_pool)
    decimal = config.ETH_DECIMAL

    return convert_dola_decimal(balance, decimal)


def get_w3_eth_balance(w3_eth, dola_pool):
    balance = w3_eth.get_balance(dola_pool)
    decimal = config.ETH_DECIMAL

    return convert_dola_decimal(balance, decimal)


# get dola pool liquidity
def eth_pool_monitor(local_logger: logging.Logger, dola_chain_id, pool_infos, q):
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    local_logger.info("start monitor dola eth pool...")

    network = config.DOLA_CHAIN_ID_TO_NETWORK[dola_chain_id]
    dola_ethereum_sdk.set_ethereum_network(network)
    if network in config.NETWORK_TO_MONITOR_RPC:
        rpc_url = config.NETWORK_TO_MONITOR_RPC[network]
        external_endpoint = [rpc_url] if rpc_url else []
    else:
        external_endpoint = []
    w3_client = dola_ethereum_init.multi_endpoints_web3(network, external_endpoint)

    dola_pool = dola_ethereum_init.get_dola_pool()

    pool_info = {}

    while True:
        try:
            for (dola_pool_id, token) in pool_infos:
                if token == config.ETH_ZERO_ADDRESS:
                    balance = get_w3_eth_balance(w3_client.eth, dola_pool)
                else:
                    balance = get_w3_erc20_balance(w3_client.eth, dola_pool, token)

                if dola_pool_id not in pool_info:
                    pool_info[dola_pool_id] = {}

                if token not in pool_info[dola_pool_id]:
                    pool_info[dola_pool_id][token] = 0

                if pool_info[dola_pool_id][token] != balance:
                    change = balance - pool_info[dola_pool_id][token]
                    local_logger.info(
                        f"dola pool {config.DOLA_POOL_ID_TO_SYMBOL[dola_pool_id]} on chain {network} balance: {balance} change: {change}")
                    pool_info[dola_pool_id][token] = balance
                    pool_balance = sum(pool_info[dola_pool_id][token] for token in pool_info[dola_pool_id])
                    q.put((dola_chain_id, dola_pool_id, pool_balance))

        except Exception as e:
            local_logger.error(e)

        time.sleep(5)


def sui_pool_monitor(local_logger: logging.Logger, pool_infos, q):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    local_logger.info("start monitor dola sui pool...")

    pool_info = {}

    while True:
        try:
            for (dola_pool_id, token) in pool_infos:
                pool_address = config.SUI_TOKEN_TO_POOL[token]
                balance = get_sui_pool_balance(pool_address)
                if dola_pool_id not in pool_info or pool_info[dola_pool_id] != balance:
                    change = balance - pool_info[dola_pool_id] if dola_pool_id in pool_info else balance
                    local_logger.info(
                        f"dola pool {config.DOLA_POOL_ID_TO_SYMBOL[dola_pool_id]} on chain sui balance: {balance} change: {change}")
                    pool_info[dola_pool_id] = balance
                    q.put((0, dola_pool_id, balance))
        except Exception as e:
            local_logger.error(e)

        time.sleep(1)


def check_pool_health(dola_pool_id, pool_info):
    total_supply = get_otoken_total_supply(dola_pool_id)
    total_debt = get_dtoken_total_supply(dola_pool_id)

    liquidity = sum(pool_info[dola_chain_id] for dola_chain_id in pool_info)
    return liquidity + total_debt + config.DOLA_RESERVES_COUNT >= total_supply


def check_dola_health(pool_infos):
    return all(
        check_pool_health(dola_pool_id, pool_infos[dola_pool_id])
        for dola_pool_id in pool_infos
    )


# check pool liquidity + total_debt > total_supply
def dola_monitor(local_logger: logging.Logger, q, value, lock):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    local_logger.info("start monitor dola protocol...")

    pool_infos = {}
    while True:
        try:
            (dola_chain_id, dola_pool_id, balance) = q.get_nowait()
            if dola_pool_id not in pool_infos:
                pool_infos[dola_pool_id] = {}

            if dola_chain_id not in pool_infos[dola_pool_id] or pool_infos[dola_pool_id][dola_chain_id] != balance:
                pool_infos[dola_pool_id][dola_chain_id] = balance
        except queue.Empty:
            local_logger.info("No new balance change!")
        except Exception as e:
            local_logger.error(e)

        health = check_dola_health(pool_infos)

        lock.acquire()
        value.value = health
        lock.release()
        if health:
            local_logger.info(f"dola protocol health: {health}")
            time.sleep(5)
        else:
            local_logger.warning(f"dola protocol health: {health}")


def get_all_pools():
    all_pools = {}

    dola_pool_ids = range(config.DOLA_RESERVES_COUNT)
    for dola_pool_id in dola_pool_ids:
        pool_infos = interfaces.get_all_pool_liquidity(dola_pool_id)['pool_infos']
        for pool_info in pool_infos:
            dola_chain_id = pool_info['pool_address']['dola_chain_id']
            token_address = bytes(pool_info['pool_address']['dola_address']).hex()
            if dola_chain_id == 0:
                token_address = bytes(pool_info['pool_address']['dola_address']).decode()

            if dola_chain_id not in all_pools:
                all_pools[dola_chain_id] = []
            all_pools[dola_chain_id].append((dola_pool_id, f'0x{token_address}'))

    return all_pools


def main():
    all_pools = get_all_pools()

    manager = Manager()

    logger = logging.getLogger("dola_monitor")

    lock = manager.Lock()

    health = manager.Value('b', True)

    q = manager.Queue()

    pt = ProcessExecutor(executor=6)

    sui_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['sui-mainnet']
    polygon_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['polygon-main']
    optimism_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['optimism-main']
    arbitrum_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['arbitrum-main']
    base_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['base-main']

    pt.run([
        # One monitoring pool balance per chain
        functools.partial(sui_pool_monitor, logger.getChild("[sui_pool_monitor]"),
                          all_pools[sui_dola_chain_id], q),
        functools.partial(eth_pool_monitor, logger.getChild("[polygon_pool_monitor]"),
                          polygon_dola_chain_id,
                          all_pools[polygon_dola_chain_id], q),
        functools.partial(eth_pool_monitor, logger.getChild("[optimism_pool_monitor]"),
                          optimism_dola_chain_id,
                          all_pools[optimism_dola_chain_id], q),
        functools.partial(eth_pool_monitor, logger.getChild("[arbitrum_pool_monitor]"),
                          arbitrum_dola_chain_id,
                          all_pools[arbitrum_dola_chain_id], q),
        functools.partial(eth_pool_monitor, logger.getChild("[base_pool_monitor]"),
                          base_dola_chain_id,
                          all_pools[base_dola_chain_id], q),
        # Protocol health monitoring
        functools.partial(dola_monitor, logger.getChild("[dola_monitor]"), q, health, lock),
    ])


if __name__ == '__main__':
    main()
