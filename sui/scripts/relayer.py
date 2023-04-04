# @Time    : 2022/12/7 17:21
# @Author  : WeiDai
# @FileName: relayer.py
import contextlib
import functools
import json
import logging
import multiprocessing
import time
from collections import OrderedDict
from multiprocessing import Queue
from pathlib import Path

import ccxt
from retrying import retry
from sui_brownie import SuiObject
from sui_brownie.parallelism import ProcessExecutor, ThreadExecutor

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
from dola_sui_sdk.load import sui_project


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

kucoin = ccxt.kucoin()
kucoin.load_markets()


@retry(stop_max_attempt_number=5)
def get_token_price(token):
    if token == "eth":
        return float(kucoin.fetch_ticker("ETH/USDT")['close'])
    elif token == "bnb":
        return float(kucoin.fetch_ticker("BNB/USDT")['close'])
    elif token == "matic":
        return float(kucoin.fetch_ticker("MATIC/USDT")['close'])
    elif token == "apt":
        return float(kucoin.fetch_ticker("APT/USDT")['close'])
    elif token == "sui":
        return float(1)


def get_token_decimal(token):
    if token in ['eth', 'matic', 'bnb']:
        return 18
    elif token == 'apt':
        return 8
    elif token == 'sui':
        return 9


def get_fee_value(amount, token='sui'):
    price = get_token_price(token)
    decimal = get_token_decimal(token)
    return price * amount / pow(10, decimal)


def get_fee_amount(value, token='sui'):
    price = get_token_price(token)
    decimal = get_token_decimal(token)
    return int(value / price * pow(10, decimal))


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


def get_dola_network(dola_chain_id):
    if dola_chain_id == 0:
        return "sui"
    elif dola_chain_id == 1:
        return "aptos"
    elif dola_chain_id == 4:
        return "bsc-test"
    elif dola_chain_id == 5:
        return "polygon-test"
    elif dola_chain_id == 1442:
        return "polygon-zk-test"


def get_gas_token(network='polygon-test'):
    if network == "sui":
        return "sui"
    elif network == "aptos":
        return "apt"
    elif "polygon" in network:
        return "matic"
    elif "bsc" in network:
        return "bnb"
    else:
        return "eth"


def execute_sui_core(app_id, call_type, vaa, relay_fee):
    gas = 0
    executed = False
    if app_id == 0:
        if call_type == 0:
            gas, executed = dola_sui_lending.core_binding(vaa, relay_fee)
        elif call_type == 1:
            gas, executed = dola_sui_lending.core_unbinding(vaa, relay_fee)
    elif app_id == 1:
        if call_type == 0:
            gas, executed = dola_sui_lending.core_supply(vaa, relay_fee)
        elif call_type == 1:
            gas, executed = dola_sui_lending.core_withdraw(vaa, relay_fee)
        elif call_type == 2:
            gas, executed = dola_sui_lending.core_borrow(vaa, relay_fee)
        elif call_type == 3:
            gas, executed = dola_sui_lending.core_repay(vaa, relay_fee)
        elif call_type == 4:
            gas, executed = dola_sui_lending.core_liquidate(vaa, relay_fee)
        elif call_type == 5:
            gas, executed = dola_sui_lending.core_as_collateral(vaa, relay_fee)
        elif call_type == 6:
            gas, executed = dola_sui_lending.core_cancel_as_collateral(vaa, relay_fee)
    return gas, executed


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

    def __delitem__(self, key):
        super(BridgeDict, self).__delitem__(key)
        write_json(self.file, self)


portal_vaa_q = Queue()
sui_withdraw_q = Queue()
aptos_withdraw_q = Queue()
eth_withdraw_q = Queue()

# Record the transactions that are not completed due to insufficient handling fees,
# which will be used for subsequent compensation. If the handling fee is too low,
# the vaa will be taken for manual processing.
unfinished_transactions = BridgeDict("unfinished_transactions.json")
# Used to record completed transactions, maybe it can be used to analyze something.
finished_transactions = BridgeDict("finished_transactions.json")
# Record the gas consumed by the relayer transaction, which is used to analyze the
# general gas of the relayer_fee, so that the front end can use the gas to calculate
# the service charge for the user.
action_gas_record = BridgeDict("action_gas_record.json")

m = multiprocessing.Manager()
relay_fee_record = m.dict()

ZERO_FEE = int(1e18)


def sui_portal_watcher():
    data = BridgeDict("sui_pool_vaa.json")
    local_logger = logger.getChild("[sui_portal_watcher]")
    local_logger.info("Start to read sui pool vaa ^-^")

    while True:
        with contextlib.suppress(Exception):
            # get vaa nonce and relay fee from relay event emitted at portal
            relay_events = dola_sui_init.query_relay_event()
            for event in relay_events:
                fields = event['event']['moveEvent']['fields']
                relay_fee_amount = int(fields['amount'])
                nonce = int(fields['nonce'])
                call_type = int(fields['call_type'])
                call_name = get_call_name(1, call_type)
                dk = f"sui_portal_{call_name}_{nonce}"

                if dk not in relay_fee_record:
                    # relay_fee_record[dk] = get_fee_value(relay_fee_amount)
                    relay_fee_record[dk] = ZERO_FEE
                    local_logger.info(f"Have a {call_name} transaction from sui, nonce: {nonce}")

                if dk not in data and call_name == 'liquidate':
                    vaa, nonce = dola_sui_init.bridge_pool_read_vaa(nonce)
                    portal_vaa_q.put((vaa, nonce, "sui"))
                    data[dk] = vaa
        time.sleep(1)


def aptos_portal_watcher():
    data = BridgeDict("aptos_pool_vaa.json")
    local_logger = logger.getChild("[aptos_portal_watcher]")
    local_logger.info("Start to read aptos pool vaa ^-^")

    while True:
        with contextlib.suppress(Exception):
            relay_events = dola_aptos_init.relay_events()
            for event in relay_events:
                nonce = int(event['nonce'])
                relay_fee_amount = int(event['amount'])
                vaa, nonce = dola_aptos_init.bridge_pool_read_vaa(nonce)
                decode_vaa = list(bytes.fromhex(
                    vaa.replace("0x", "") if "0x" in vaa else vaa))
                call_name = get_call_name(decode_vaa[1], decode_vaa[-1])
                dk = f"aptos_portal_{call_name}_{str(nonce)}"

                if dk not in data:
                    # relay_fee_record[dk] = get_fee_value(relay_fee_amount, 'apt')
                    relay_fee_record[dk] = ZERO_FEE
                    portal_vaa_q.put((vaa, nonce, "aptos"))
                    data[dk] = vaa
                    local_logger.info(f"Have a {call_name} transaction from aptos, nonce: {nonce}")
        time.sleep(1)


def eth_portal_watcher(network="polygon-test"):
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(network)
    data = BridgeDict(f"{network}_pool_vaa.json")
    # Ethereum start block
    start_block_record = BridgeDict("start_block_record.json")

    local_logger = logger.getChild(f"[{network}_portal_watcher]")
    local_logger.info(f"Start to read {network} pool vaa ^-^")

    if network not in start_block_record:
        start_block_record[network] = 0

    while True:
        with contextlib.suppress(Exception):
            start_block = start_block_record[network]
            current_block_number = dola_ethereum_init.current_block_number()
            relay_events = dola_ethereum_init.relay_events(start_block=start_block,
                                                           end_block=current_block_number)

            for nonce in relay_events:
                vaa, nonce = dola_ethereum_init.bridge_pool_read_vaa(nonce)
                decode_vaa = list(bytes.fromhex(
                    vaa.replace("0x", "") if "0x" in vaa else vaa))
                call_name = get_call_name(decode_vaa[1], decode_vaa[-1])
                dk = f"{network}_portal_{call_name}_{str(nonce)}"
                if dk not in data:
                    gas_token = get_gas_token(network)

                    # relay_fee_record[dk] = get_fee_value(relay_events[nonce], gas_token)
                    relay_fee_record[dk] = ZERO_FEE

                    portal_vaa_q.put((vaa, nonce, network))
                    start_block_record[network] = current_block_number
                    data[dk] = vaa
                    local_logger.info(f"Have a {call_name} transaction from {network}, nonce: {nonce}")
        time.sleep(1)


def pool_withdraw_watcher():
    sui_omnipool = dola_sui_load.omnipool_package()
    data = BridgeDict("pool_withdraw_vaa.json")
    local_logger = logger.getChild("[pool_withdraw_watcher]")
    local_logger.info("Start to read withdraw vaa ^-^")
    while True:
        with contextlib.suppress(Exception):
            vaa, nonce = dola_sui_init.bridge_core_read_vaa()
            result = sui_omnipool.wormhole_adapter_pool.decode_withdraw_payload.simulate(
                vaa)
            decode_payload = result["events"][-1]["parsedJson"]
            token_name = decode_payload["pool_address"]["dola_address"]
            dola_chain_id = decode_payload["pool_address"]["dola_chain_id"]
            if dola_chain_id in [0, 1]:
                token_name = bytes(token_name).decode("ascii")
                if token_name[:2] != "0x":
                    token_name = f"0x{token_name}"

            dk = f"pool_withdraw_{dola_chain_id}_{str(nonce)}"
            if dk not in data:
                source_chain_id = decode_payload["source_chain_id"]
                source_nonce = decode_payload["nonce"]
                call_type = decode_payload["call_type"]
                call_name = get_call_name(1, int(call_type))
                network = get_dola_network(source_chain_id)

                if dola_chain_id == 0:
                    sui_withdraw_q.put((vaa, source_chain_id, source_nonce, call_type, token_name))
                    local_logger.info(
                        f"Have a {call_name} from {network} to sui, nonce: {nonce}, token: {token_name}")
                elif dola_chain_id == 1:
                    aptos_withdraw_q.put((vaa, source_chain_id, source_nonce, call_type, token_name))
                    local_logger.info(
                        f"Have a {call_name} from {network} to aptos, nonce: {nonce}, token: {token_name}")
                else:
                    eth_withdraw_q.put((vaa, source_chain_id, source_nonce, call_type, dola_chain_id))
                    local_logger.info(
                        f"Have a {call_name} from {network} to {get_dola_network(dola_chain_id)}, nonce: {nonce}")
                data[dk] = vaa
        time.sleep(1)


def sui_core_executor():
    data = BridgeDict("sui_core_executed_vaa.json")
    local_logger = logger.getChild("[sui_core_executor]")
    local_logger.info("Start to relay pool vaa ^-^")
    while True:
        try:
            (vaa, nonce, chain) = portal_vaa_q.get()
            decode_vaa = list(bytes.fromhex(
                vaa.replace("0x", "") if "0x" in vaa else vaa))
            app_id = decode_vaa[1]
            call_type = decode_vaa[-1]
            call_name = get_call_name(app_id, call_type)
            dk = f"{chain}_portal_{call_name}_{nonce}"

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]
                relay_fee = get_fee_amount(relay_fee_value)

                sui_project.active_account("Relayer1")
                gas, executed = execute_sui_core(app_id, call_type, decode_vaa, relay_fee)
                gas_price = 1000
                gas_amount = gas * gas_price
                if executed:
                    if call_name in ["withdraw", "borrow"]:
                        relay_fee_record[dk] = get_fee_value(relay_fee - gas_amount)
                    else:
                        finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                     "consumed_fee": get_fee_value(gas_amount)}
                        del relay_fee_record[dk]
                        action_gas_record[f"sui_{call_name}"] = gas
                    data[dk] = vaa
                    local_logger.info("Execute sui core success! ")
                    local_logger.info(f"call: {call_name} source: {chain}, nonce: {nonce}")
                    local_logger.info(
                        f"relay fee: {relay_fee_value}, consumed fee: {get_fee_value(gas_amount)}")
                else:
                    unfinished_transactions[f"core_{dk}"] = {"vaa": str(vaa), "nonce": nonce, "chain": chain,
                                                             "relay_fee": relay_fee_record[dk]}

                    local_logger.warning("Execute sui core fail, not enough relay fee! ")
                    local_logger.warning(
                        f"Need gas fee: {get_fee_value(gas_amount)}, but available gas fee: {relay_fee_value}")
                    local_logger.warning(f"call: {call_name} source: {chain}, nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Execute sui core fail\n {e}")


def sui_pool_executor():
    data = BridgeDict("sui_pool_executed_vaa.json")
    local_logger = logger.getChild("[sui_pool_executor]")
    local_logger.info("Start to relay sui withdraw vaa ^-^")

    sui_wormhole = dola_sui_load.wormhole_package()
    sui_omnipool = dola_sui_load.omnipool_package()
    while True:
        try:
            (vaa, source_chain_id, source_nonce, call_type, token_name) = sui_withdraw_q.get()
            chain = get_dola_network(source_chain_id)
            call_name = get_call_name(1, int(call_type))
            dk = f"{chain}_portal_{call_name}_{source_nonce}"

            # todo: removed after fixing sui_watcher
            if dk not in relay_fee_record:
                relay_fee_record[dk] == ZERO_FEE

            if dk not in data:
                sui_account_address = sui_omnipool.account.account_address

                relay_fee_value = relay_fee_record[dk]

                avaliable_gas_amount = get_fee_amount(relay_fee_value, 'sui')

                sui_project.active_account("Relayer2")
                result = sui_omnipool.wormhole_adapter_pool.receive_withdraw.simulate(
                    sui_wormhole.state.State[-1],
                    sui_omnipool.dola_pool.PoolApproval[-1],
                    sui_omnipool.wormhole_adapter_pool.PoolState[-1],
                    sui_project[SuiObject.from_type(
                        dola_sui_init.pool(token_name))][sui_account_address][-1],
                    vaa,
                    type_arguments=[token_name]
                )
                gas_used = dola_sui_lending.calculate_sui_gas(result['effects']['gasUsed'])
                gas_price = 1000

                tx_gas_amount = int(gas_used) * gas_price
                if avaliable_gas_amount > tx_gas_amount:
                    sui_omnipool.wormhole_adapter_pool.receive_withdraw(
                        sui_wormhole.state.State[-1],
                        sui_omnipool.dola_pool.PoolApproval[-1],
                        sui_omnipool.wormhole_adapter_pool.PoolState[-1],
                        sui_project[SuiObject.from_type(
                            dola_sui_init.pool(token_name))][sui_account_address][-1],
                        vaa,
                        type_arguments=[token_name]
                    )
                    finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                 "consumed_fee": get_fee_value(tx_gas_amount)}
                    del relay_fee_record[dk]
                    action_gas_record[f"sui_{call_name}"] = gas_used

                    data[dk] = vaa
                    local_logger.info("Execute sui withdraw success! ")
                    local_logger.info(
                        f"token: {token_name} source: {chain} nonce: {source_nonce}")
                    local_logger.info(f"relay fee: {relay_fee_value}, consumed fee: {get_fee_value(tx_gas_amount)}")
                else:
                    unfinished_transactions[f"sui_pool_{dk}"] = {"vaa": vaa,
                                                                 "source_chain_id": source_chain_id,
                                                                 "source_nonce": source_nonce,
                                                                 "call_type": call_type,
                                                                 "token_name": token_name,
                                                                 "relay_fee": relay_fee_record[dk]
                                                                 }

                    local_logger.warning("Execute withdraw fail on sui, not enough relay fee! ")
                    local_logger.warning(
                        f"Need gas fee: {get_fee_value(tx_gas_amount)}, but available gas fee: {relay_fee_value}"
                    )
                    local_logger.warning(
                        f"call: {call_name} source: {chain}, nonce: {source_nonce}")
        except Exception as e:
            local_logger.error(f"Execute sui pool withdraw fail\n {e}")


def aptos_pool_executor():
    data = BridgeDict("aptos_pool_executed_vaa.json")
    local_logger = logger.getChild("[aptos_pool_executor]")
    local_logger.info("Start to relay aptos withdraw vaa ^-^")

    aptos_omnipool = dola_aptos_load.omnipool_package()

    while True:
        try:
            (vaa, source_chain_id, source_nonce, call_type, token_name) = aptos_withdraw_q.get()
            chain = get_dola_network(source_chain_id)
            call_name = get_call_name(1, int(call_type))
            dk = f"{chain}_portal_{call_name}_{source_nonce}"

            # todo: removed after fixing sui_watcher
            if dk not in relay_fee_record:
                relay_fee_record[dk] == ZERO_FEE

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]
                avaliable_gas_amount = get_fee_amount(relay_fee_value, 'apt')

                gas_used = aptos_omnipool.wormhole_adapter_pool.receive_withdraw.simulate(
                    vaa,
                    type_arguments=[token_name],
                    return_types="gas"
                )
                gas_price = aptos_omnipool.estimate_gas_price()
                tx_gas_amount = int(gas_used) * int(gas_price)
                if avaliable_gas_amount > tx_gas_amount:
                    aptos_omnipool.wormhole_adapter_pool.receive_withdraw(
                        vaa,
                        type_arguments=[token_name]
                    )
                    finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                 "consumed_fee": get_fee_value(tx_gas_amount)}
                    del relay_fee_record[dk]
                    action_gas_record[f"aptos_{call_name}"] = gas_used
                    data[dk] = vaa

                    local_logger.info("Execute aptos withdraw success! ")
                    local_logger.info(
                        f"token: {token_name} source: {chain} nonce: {source_nonce}")
                    local_logger.info(
                        f"relay fee: {relay_fee_value}, consumed fee: {get_fee_value(tx_gas_amount, 'apt')}")
                else:
                    unfinished_transactions[f"aptos_pool_{dk}"] = {"vaa": vaa,
                                                                   "source_chain_id": source_chain_id,
                                                                   "source_nonce": source_nonce,
                                                                   "call_type": call_type,
                                                                   "token_name": token_name,
                                                                   "relay_fee": relay_fee_record[dk]
                                                                   }
                    local_logger.warning("Execute withdraw fail on aptos, not enough relay fee! ")
                    local_logger.warning(
                        f"Need gas fee: {get_fee_value(tx_gas_amount, 'apt')}, but available gas fee: {relay_fee_value}")
                    local_logger.warning(
                        f"call: {call_name} source: {chain}, nonce: {source_nonce}")
        except Exception as e:
            local_logger.error(f"Execute aptos pool withdraw fail\n {e}")


def eth_pool_executor():
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    data = BridgeDict("eth_pool_executed_vaa.json")
    local_logger = logger.getChild("[eth_pool_executor]")
    local_logger.info("Start to relay eth withdraw vaa ^-^")

    while True:
        try:
            (vaa, source_chain_id, source_nonce, call_type, dola_chain_id) = eth_withdraw_q.get()
            network = get_dola_network(dola_chain_id)
            dola_ethereum_sdk.set_ethereum_network(network)

            ethereum_wormhole_bridge = dola_ethereum_load.wormhole_adapter_pool_package()
            ethereum_account = dola_ethereum_sdk.get_account()
            call_name = get_call_name(1, int(call_type))
            source_chain = get_dola_network(source_chain_id)
            dk = f"{source_chain}_portal_{call_name}_{source_nonce}"

            # todo: removed after fixing sui_watcher
            if dk not in relay_fee_record:
                relay_fee_record[dk] == ZERO_FEE

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]
                available_gas_amount = get_fee_amount(relay_fee_value, get_gas_token(network))

                # todo: get real-time gas price
                gas_price = 1
                gas_used = ethereum_wormhole_bridge.receiveWithdraw.estimate_gas(
                    vaa, {"from": ethereum_account})

                tx_gas_amount = int(gas_used) * gas_price
                if available_gas_amount > tx_gas_amount:
                    ethereum_wormhole_bridge.receiveWithdraw(
                        vaa, {"from": ethereum_account})

                    finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                 "consumed_fee": get_fee_value(tx_gas_amount)}
                    del relay_fee_record[dk]
                    action_gas_record[f"{network}_{call_name}"] = gas_used

                    data[dk] = vaa
                    local_logger.info(f"Execute {network} withdraw success! ")
                    local_logger.info(f"source: {source_chain} nonce: {source_nonce}")
                    local_logger.info(
                        f"relay fee: {relay_fee_value}, consumed fee: {get_fee_value(tx_gas_amount, get_gas_token(network))}")
                else:
                    unfinished_transactions[f"{network}_pool_{dk}"] = {"vaa": vaa,
                                                                       "source_chain_id": source_chain_id,
                                                                       "source_nonce": source_nonce,
                                                                       "call_type": call_type,
                                                                       "dola_chain_id": dola_chain_id,
                                                                       "relay_fee": relay_fee_record[dk]
                                                                       }
                    local_logger.warning(
                        f"Execute withdraw fail on {get_dola_network(dola_chain_id)}, not enough relay fee! ")
                    local_logger.warning(
                        f"Need gas fee: {get_fee_value(tx_gas_amount, get_gas_token(network))}, but available gas fee: {relay_fee_value}")
                    local_logger.warning(
                        f"call: {call_name} source: {source_chain}, nonce: {source_nonce}")
        except Exception as e:
            local_logger.error(f"Execute eth pool withdraw fail\n {e}")


def compensate_unfinished_transaction():
    # todo: Monitor Wormhole vaa whether it has been executed for compensation.
    while True:
        unfinished_transactions.read_data()
        # Priority compensation for more relayer fee
        keys = sorted(unfinished_transactions, reverse=True, key=lambda i: unfinished_transactions[i]['relay_fee'])
        # todo: Calculate relay_fee using Action Gas to ensure that the compensated
        #       transaction relay_fee is enough to put in the queue.
        for k in keys:
            if "core" in k:
                dk = str(k).removeprefix('core_')
                portal_data = unfinished_transactions[k]
                relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']

                portal_vaa_q.put((portal_data['vaa'], portal_data['nonce'], portal_data['chain']))
            elif "sui_pool" in k:
                dk = str(k).removeprefix('sui_pool_')
                withdraw_data = unfinished_transactions[k]
                relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
                sui_withdraw_q.put((withdraw_data['vaa'],
                                    withdraw_data['source_chain_id'],
                                    withdraw_data['source_nonce'],
                                    withdraw_data['call_type'],
                                    withdraw_data['token_name']))
            elif "aptos_pool" in k:
                dk = str(k).removeprefix('aptos_pool_')
                withdraw_data = unfinished_transactions[k]
                relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
                aptos_withdraw_q.put((withdraw_data['vaa'],
                                      withdraw_data['source_chain_id'],
                                      withdraw_data['source_nonce'],
                                      withdraw_data['call_type'],
                                      withdraw_data['token_name']))
            else:
                dk = str(k).split('_')[1]
                withdraw_data = unfinished_transactions[k]
                relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
                eth_withdraw_q.put((withdraw_data['vaa'],
                                    withdraw_data['source_chain_id'],
                                    withdraw_data['source_nonce'],
                                    withdraw_data['call_type'],
                                    withdraw_data['dola_chain_id']))


def run_aptos_relayer():
    dola_aptos_sdk.set_dola_project_path(Path("../.."))
    pt = ThreadExecutor(executor=2)

    pt.run([
        aptos_portal_watcher,
        aptos_pool_executor
    ])


def run_sui_relayer():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    pt = ThreadExecutor(executor=4)

    pt.run([
        pool_withdraw_watcher,
        sui_portal_watcher,
        sui_core_executor,
        sui_pool_executor
    ])


def main():
    pt = ProcessExecutor(executor=6)

    pt.run([
        run_sui_relayer,
        run_aptos_relayer,
        functools.partial(eth_portal_watcher, "polygon-test"),
        functools.partial(eth_portal_watcher, "bsc-test"),
        functools.partial(eth_portal_watcher, "polygon-zk-test"),
        eth_pool_executor,
    ])


if __name__ == "__main__":
    main()
