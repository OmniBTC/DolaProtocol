# @Time    : 2022/12/7 17:21
# @Author  : WeiDai
# @FileName: relayer.py
import contextlib
import functools
import json
import logging
import time
from collections import OrderedDict
from pathlib import Path
from queue import Queue

from sui_brownie import CacheObject, ObjectType
from sui_brownie.parallelism import ThreadExecutor

import dola_aptos_sdk
import dola_aptos_sdk.init as dola_aptos_init
import dola_aptos_sdk.load as dola_aptos_load
import dola_ethereum_sdk
import dola_ethereum_sdk.init as dola_ethereum_init
import dola_ethereum_sdk.load as dola_ethereum_load
import dola_sui_sdk
import dola_sui_sdk.init as dola_sui_init
import dola_sui_sdk.lending as dola_sui_lending
import dola_sui_sdk.load as dola_sui_load


class ColorFormatter(logging.Formatter):
    grey = '\x1b[38;21m'
    green = '\x1b[92m'
    yellow = '\x1b[38;5;226m'
    red = '\x1b[38;5;196m'
    bold_red = '\x1b[31;1m'
    reset = '\x1b[0m'

    def __init__(self, fmt):
        super().__init__()
        self.fmt = fmt
        self.FORMATS = {
            logging.DEBUG: self.grey + self.fmt + self.reset,
            logging.INFO: self.green + self.fmt + self.reset,
            logging.WARNING: self.yellow + self.fmt + self.reset,
            logging.ERROR: self.red + self.fmt + self.reset,
            logging.CRITICAL: self.bold_red + self.fmt + self.reset
        }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno)
        formatter = logging.Formatter(log_fmt)
        return formatter.format(record)


FORMAT = '%(asctime)s - %(funcName)s - %(levelname)s - %(name)s: %(message)s'
logger = logging.getLogger()
logger.setLevel("INFO")
# create console handler with a higher log level
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)

ch.setFormatter(ColorFormatter(FORMAT))

logger.addHandler(ch)


def get_call_name(app_id, call_type):
    if app_id == 0:
        if call_type == 0:
            return "binding"
        elif call_type == 1:
            return "unbinding"
    elif app_id == 1:
        if call_type == 0:
            return "supply"
        elif call_type == 1:
            return "withdraw"
        elif call_type == 2:
            return "borrow"
        elif call_type == 3:
            return "repay"
        elif call_type == 4:
            return "liquidate"
        elif call_type == 5:
            return "as_collateral"
        elif call_type == 6:
            return "cancel_as_collateral"


def get_eth_network(dola_chain_id):
    if dola_chain_id == 4:
        return "bsc-test"
    elif dola_chain_id == 5:
        return "polygon-test"
    elif dola_chain_id == 1442:
        return "polygon-zk-test"


def execute_sui_core(app_id, call_type, vaa):
    if app_id == 0:
        if call_type == 0:
            dola_sui_lending.core_binding(vaa)
        elif call_type == 1:
            dola_sui_lending.core_unbinding(vaa)
    elif app_id == 1:
        if call_type == 0:
            dola_sui_lending.core_supply(vaa)
        elif call_type == 1:
            dola_sui_lending.core_withdraw(vaa)
        elif call_type == 2:
            dola_sui_lending.core_borrow(vaa)
        elif call_type == 3:
            dola_sui_lending.core_repay(vaa)
        elif call_type == 4:
            dola_sui_lending.core_liquidate(vaa)
        elif call_type == 5:
            dola_sui_lending.core_as_collateral(vaa)
        elif call_type == 6:
            dola_sui_lending.core_cancel_as_collateral(vaa)


def read_json(file) -> dict:
    try:
        with open(file, "r") as f:
            return json.load(f)
    except Exception:
        return {}


def write_json(file, data: dict):
    with open(file, "w") as f:
        return json.dump(data, f, indent=1, separators=(',', ':'))


class BridgeDict(OrderedDict):
    def __init__(self, file, *args, **kwargs):
        pool_path = Path.home().joinpath(".cache").joinpath(
            "sui").joinpath("bridge_records")
        if not pool_path.exists():
            pool_path.mkdir()
        pool_file = pool_path.joinpath(file)
        self.file = pool_file
        super(BridgeDict, self).__init__(*args, **kwargs)
        self.read_data()

    def read_data(self):
        data = read_json(self.file)
        for k in data:
            self[k] = data[k]

    def __setitem__(self, key, value):
        super(BridgeDict, self).__setitem__(key, value)
        write_json(self.file, self)


def read_sui_pool_vaa(q: Queue):
    data = BridgeDict("sui_pool_vaa.json")
    local_logger = logger.getChild("[sui_pool]")
    local_logger.info("Start to read sui pool vaa ^-^")

    while True:
        with contextlib.suppress(Exception):
            # Read sui
            vaa, nonce = dola_sui_init.bridge_pool_read_vaa()
            decode_vaa = list(bytes.fromhex(
                vaa.replace("0x", "") if "0x" in vaa else vaa))
            call_type = get_call_name(decode_vaa[1], decode_vaa[-1])
            dk = f"sui_pool_{str(nonce)}"
            if dk not in data:
                q.put((vaa, nonce, "sui"))
                data[dk] = vaa
                local_logger.info(f"Have a {call_type} transaction from sui, nonce: {nonce}")
        time.sleep(1)


def read_aptos_pool_vaa(q: Queue):
    data = BridgeDict("aptos_pool_vaa.json")
    local_logger = logger.getChild("[aptos_pool]")
    local_logger.info("Start to read aptos pool vaa ^-^")

    while True:
        with contextlib.suppress(Exception):
            # Read sui
            vaa, nonce = dola_aptos_init.bridge_pool_read_vaa()
            decode_vaa = list(bytes.fromhex(
                vaa.replace("0x", "") if "0x" in vaa else vaa))
            call_name = get_call_name(decode_vaa[1], decode_vaa[-1])
            dk = f"aptos_pool_{call_name}_{str(nonce)}"
            if dk not in data:
                q.put((vaa, nonce, "sui"))
                data[dk] = vaa
                local_logger.info(f"Have a {call_name} transaction from aptos, nonce: {nonce}")
        time.sleep(1)


def read_eth_pool_vaa(q: Queue, network="polygon-test"):
    dola_ethereum_sdk.set_ethereum_network(network)
    data = BridgeDict(f"{network}_pool_vaa.json")
    local_logger = logger.getChild(f"[{network}_pool]")
    local_logger.info(f"Start to read {network} pool vaa ^-^")
    while True:
        with contextlib.suppress(Exception):
            # Read sui
            vaa, nonce = dola_ethereum_init.bridge_pool_read_vaa()
            decode_vaa = list(bytes.fromhex(
                vaa.replace("0x", "") if "0x" in vaa else vaa))
            call_name = get_call_name(decode_vaa[1], decode_vaa[-1])
            dk = f"{network}_pool_{call_name}_{str(nonce)}"
            if dk not in data:
                q.put((vaa, nonce, "sui"))
                data[dk] = vaa
                local_logger.info(f"Have a {call_name} transaction from {network}, nonce: {nonce}")
        time.sleep(1)


def read_withdraw_vaa(sui_q: Queue, aptos_q: Queue, eth_q: Queue):
    sui_omnipool = dola_sui_load.omnipool_package()
    data = BridgeDict("pool_withdraw_vaa.json")
    local_logger = logger.getChild("[pool_withdraw]")
    while True:
        try:
            vaa, nonce = dola_sui_init.bridge_core_read_vaa()
            result = sui_omnipool.wormhole_adapter_pool.decode_withdraw_payload.simulate(
                vaa)
            decode_payload = result["events"][-1]["moveEvent"]["fields"]["pool_address"]["fields"]
            token_name = decode_payload["dola_address"]
            dola_chain_id = decode_payload["dola_chain_id"]
            if dola_chain_id in [0, 1]:
                token_name = bytes(token_name).decode("ascii")
                if token_name[:2] != "0x":
                    token_name = f"0x{token_name}"

            dk = f"withdraw_pool_{dola_chain_id}_{str(nonce)}"
            if dk not in data:
                if dola_chain_id == 0:
                    sui_q.put((vaa, nonce, token_name))
                elif dola_chain_id == 1:
                    aptos_q.put((vaa, nonce, token_name))
                else:
                    eth_q.put((vaa, nonce, dola_chain_id))
                data[dk] = vaa
        except Exception as e:
            local_logger.info(f"read withdraw vaa fail: {e}")
        time.sleep(1)


def sui_core_executor(q: Queue):
    data = BridgeDict("sui_core_executed_vaa.json")
    local_logger = logger.getChild("[sui_core]")
    local_logger.info("Start to relay pool vaa ^-^")
    while True:
        try:
            (vaa, nonce, chain) = q.get()
            decode_vaa = list(bytes.fromhex(
                vaa.replace("0x", "") if "0x" in vaa else vaa))
            app_id = decode_vaa[1]
            call_type = decode_vaa[-1]
            call_name = get_call_name(app_id, call_type)

            dk = f"{chain}_pool_{call_name}_{nonce}"
            if dk not in data:
                execute_sui_core(app_id, call_type, decode_vaa)
                data[dk] = vaa
                local_logger.info(f"Execute sui core success, call: {call_name} source: {chain}, nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Execute sui core fail\n {e}")


def sui_pool_executor(q: Queue):
    data = BridgeDict("sui_pool_executed_vaa.json")
    local_logger = logger.getChild("[sui_pool]")
    local_logger.info("Start to relay sui withdraw vaa ^-^")

    sui_wormhole = dola_sui_load.wormhole_package()
    sui_omnipool = dola_sui_load.omnipool_package()
    while True:
        try:
            (vaa, nonce, token_name) = q.get()
            dk = f"sui_pool_withdraw_{nonce}"
            if dk not in data:
                sui_account_address = sui_omnipool.account.account_address

                sui_omnipool.wormhole_adapter_pool.receive_withdraw(
                    sui_wormhole.state.State[-1],
                    sui_omnipool.bridge_pool.PoolState[-1],
                    CacheObject[ObjectType.from_type(
                        dola_sui_init.pool(token_name))][sui_account_address][-1],
                    vaa,
                    ty_args=[token_name]
                )

                data[dk] = vaa

                local_logger.info(f"Execute sui withdraw success, token: {token_name} nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Execute sui pool withdraw fail\n {e}")


def aptos_pool_executor(q: Queue):
    data = BridgeDict("aptos_pool_executed_vaa.json")
    local_logger = logger.getChild("[aptos_pool]")
    local_logger.info("Start to relay aptos withdraw vaa ^-^")

    aptos_omnipool = dola_aptos_load.omnipool_package()

    while True:
        try:
            (vaa, nonce, token_name) = q.get()
            dk = f"aptos_pool_withdraw_{nonce}"
            if dk not in data:
                aptos_omnipool.wormhole_adapter_pool.receive_withdraw(
                    vaa,
                    ty_args=[token_name]
                )

                data[dk] = vaa

                local_logger.info(f"Execute aptos withdraw success, token: {token_name} nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Execute aptos pool withdraw fail\n {e}")


def eth_pool_executor(q: Queue):
    data = BridgeDict("eth_pool_executed_vaa.json")
    local_logger = logger.getChild("[eth_pool]")
    local_logger.info("Start to relay eth withdraw vaa ^-^")

    while True:
        try:
            (vaa, nonce, dola_chain_id) = q.get()
            network = get_eth_network(dola_chain_id)
            dola_ethereum_sdk.set_ethereum_network(network)

            ethereum_wormhole_bridge = dola_ethereum_load.wormhole_adapter_pool_package()
            ethereum_account = dola_ethereum_sdk.get_account()
            dk = f"{network}_pool_withdraw_{nonce}"
            if dk not in data:
                ethereum_wormhole_bridge.receiveWithdraw(
                    vaa, {"from": ethereum_account})

                data[dk] = vaa

                local_logger.info(f"Execute {network} withdraw success, nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Execute eth pool withdraw fail\n {e}")


def main():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    pt = ThreadExecutor(executor=8)
    pool_vaa_q = Queue()
    sui_withdraw_q = Queue()
    aptos_withdraw_q = Queue()
    eth_withdraw_q = Queue()
    pt.run([functools.partial(read_withdraw_vaa, sui_withdraw_q, aptos_withdraw_q, eth_withdraw_q),
            functools.partial(sui_pool_executor, sui_withdraw_q),
            functools.partial(aptos_pool_executor, aptos_withdraw_q),
            functools.partial(eth_pool_executor, eth_withdraw_q),
            functools.partial(read_sui_pool_vaa, pool_vaa_q),
            functools.partial(read_aptos_pool_vaa, pool_vaa_q),
            functools.partial(read_eth_pool_vaa, pool_vaa_q, "polygon-test"),
            functools.partial(sui_core_executor, pool_vaa_q)])


if __name__ == "__main__":
    main()
