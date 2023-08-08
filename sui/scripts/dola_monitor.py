# dola protocol monitor
import functools
import logging
import queue
import time
from multiprocessing import Manager
from pathlib import Path

import brownie
from sui_brownie.parallelism import ProcessExecutor

import config
import dola_ethereum_sdk
import dola_sui_sdk
from dola_ethereum_sdk import load as dola_ethereum_load, init as dola_ethereum_init
from dola_sui_sdk import load as dola_sui_load, sui_project, interfaces


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


def get_eth_balance(dola_pool):
    balance = brownie.web3.eth.get_balance(dola_pool)
    decimal = config.ETH_DECIMAL

    return convert_dola_decimal(balance, decimal)


# get dola pool liquidity
def eth_pool_monitor(local_logger: logging.Logger, dola_chain_id, pool_infos, q):
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    local_logger.info("start monitor dola eth pool...")

    network = config.DOLA_CHAIN_ID_TO_NETWORK[dola_chain_id]
    dola_ethereum_sdk.set_ethereum_network(network)

    dola_pool = dola_ethereum_init.get_dola_pool()

    pool_info = {}

    while True:
        try:
            for (dola_pool_id, token) in pool_infos:
                if token == config.ETH_ZERO_ADDRESS:
                    balance = get_eth_balance(dola_pool)
                else:
                    balance = get_erc20_balance(dola_pool, token)

                if dola_pool_id not in pool_info or pool_info[dola_pool_id] != balance:
                    pool_info[dola_pool_id] = balance
                    q.put((dola_chain_id, dola_pool_id, balance))
        except Exception as e:
            local_logger.error(e)

        time.sleep(1)


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
                    pool_info[dola_pool_id] = balance
                    q.put((0, dola_pool_id, balance))
        except Exception as e:
            local_logger.error(e)

        time.sleep(1)


def check_pool_health(dola_pool_id, pool_info):
    total_supply = get_otoken_total_supply(dola_pool_id)
    total_debt = get_dtoken_total_supply(dola_pool_id)

    liquidity = sum(pool_info[dola_chain_id] for dola_chain_id in pool_info)
    return liquidity + total_debt >= total_supply


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
            local_logger.info(
                f"dola pool {dola_pool_id} on chain {config.DOLA_CHAIN_ID_TO_NETWORK[dola_chain_id]} balance: {balance}")
            if dola_pool_id not in pool_infos:
                pool_infos[dola_pool_id] = {}

            if dola_chain_id not in pool_infos[dola_pool_id] or pool_infos[dola_pool_id][dola_chain_id] != balance:
                pool_infos[dola_pool_id][dola_chain_id] = balance
        except queue.Empty:
            local_logger.info("No new balance change!")
        except Exception as e:
            local_logger.error(e)

        health = check_dola_health(pool_infos)
        if health:
            local_logger.info(f"dola protocol health: {health}")
        else:
            local_logger.warning(f"dola protocol health: {health}")
        lock.acquire()
        value.value = health
        lock.release()
        time.sleep(1)


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

            # todo: testnet fix, remove later
            if dola_chain_id == 5:
                continue
            if dola_chain_id not in all_pools:
                all_pools[dola_chain_id] = []
            all_pools[dola_chain_id].append((dola_pool_id, f'0x{token_address}'))

    return all_pools


def main():
    all_pools = get_all_pools()
    monitor_num = len(all_pools.keys())

    manager = Manager()

    value = manager.Value('b', True)

    lock = manager.Lock()

    q = manager.Queue()

    pt = ProcessExecutor(executor=monitor_num + 1)

    pt.run([
        functools.partial(sui_pool_monitor, all_pools[0], q),
        functools.partial(eth_pool_monitor, 6, all_pools[6], q),
        functools.partial(dola_monitor, q, value, lock)
    ])


if __name__ == '__main__':
    main()
