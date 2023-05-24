import base64
import functools
import json
import logging
import multiprocessing
import time
import traceback
from collections import OrderedDict
from multiprocessing import Queue
from pathlib import Path
from pprint import pprint

import brownie.network
import ccxt
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
import requests
from dola_sui_sdk.load import sui_project
from retrying import retry
from sui_brownie import Argument, U16
from sui_brownie.parallelism import ProcessExecutor, ThreadExecutor


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


@retry
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
        return float(kucoin.fetch_ticker("SUI/USDT")['close'])


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
    elif dola_chain_id == 7:
        return "polygon-zk-test"
    elif dola_chain_id == 8:
        return "arbitrum-test"
    elif dola_chain_id == 9:
        return "optimism-test"
    else:
        return "unknown"


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

fee_record_lock = m.Lock()
start_block_lock = m.Lock()
index_lock = m.Lock()

account_index = m.Value('i', 0)


def rotate_accounts():
    global account_index
    index_lock.acquire()
    index = account_index.get()
    index += 1
    num = index % 4
    # todo: change to real account
    sui_project.active_account("TestAccount")
    # sui_project.active_account(f"Relayer{num}")
    account_index.set(index)
    index_lock.release()


ZERO_FEE = int(1e18)


def sui_portal_watcher():
    local_logger = logger.getChild("[sui_portal_watcher]")
    local_logger.info("Start to read sui pool vaa ^-^")

    while True:
        try:
            # get vaa nonce and relay fee from relay event emitted at portal
            relay_events = dola_sui_init.query_portal_relay_event()

            for event in relay_events:
                fields = event['parsedJson']
                # relay_fee_amount = int(fields['fee_amount'])
                nonce = int(fields['nonce'])
                call_type = int(fields['call_type'])
                call_name = get_call_name(1, call_type)
                dk = f"sui_portal_{call_name}_{nonce}"

                if dk not in relay_fee_record:
                    # relay_fee_record[dk] = get_fee_value(relay_fee_amount)
                    fee_record_lock.acquire()
                    relay_fee_record[dk] = ZERO_FEE
                    fee_record_lock.release()
                    local_logger.info(f"Have a {call_name} transaction from sui, nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Error: {e}")
        time.sleep(5)


def aptos_portal_watcher():
    time.sleep(10)
    data = BridgeDict("aptos_pool_vaa.json")
    local_logger = logger.getChild("[aptos_portal_watcher]")
    local_logger.info("Start to read aptos pool vaa ^-^")

    while True:
        try:
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
                    fee_record_lock.acquire()
                    relay_fee_record[dk] = ZERO_FEE
                    fee_record_lock.release()

                    portal_vaa_q.put((vaa, nonce, "aptos"))
                    data[dk] = vaa
                    local_logger.info(f"Have a {call_name} transaction from aptos, nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Error: {e}")
        time.sleep(1)


def eth_portal_watcher(network="polygon-test"):
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(network)
    data = BridgeDict(f"{network}_pool_vaa.json")
    # Ethereum start block
    start_block_record = BridgeDict("start_block_record.json")

    local_logger = logger.getChild(f"[{network}_portal_watcher]")
    local_logger.info(f"Start to read {network} pool vaa ^-^")

    wormhole = dola_ethereum_load.womrhole_package(network)
    lending_portal = dola_ethereum_load.lending_portal_package(network).address
    system_portal = dola_ethereum_load.system_portal_package(network).address

    if network not in start_block_record:
        start_block_record[network] = 0

    while True:
        try:
            start_block = start_block_record[network]
            relay_events = dola_ethereum_init.relay_events(lending_portal, system_portal,
                                                           start_block=start_block, net=network)

            if bool(relay_events):
                local_logger.info(f"Relaying events: {relay_events}")

            for block_number in sorted(relay_events):
                sequence = relay_events[block_number][0]

                # get vaa
                vaa = get_signed_vaa_by_wormhole(WORMHOLE_EMITTER_ADDRESS[network], sequence, network)
                # parse vaa
                vm = wormhole.parseVM(vaa)
                # parse payload
                payload = list(vm)[7]

                app_id = payload[1]
                call_type = payload[-1]
                call_name = get_call_name(app_id, call_type)
                dk = f"{network}_portal_{call_name}_{str(sequence)}"
                if dk not in data:
                    # gas_token = get_gas_token(network)

                    # relay_fee_record[dk] = get_fee_value(relay_events[nonce], gas_token)
                    fee_record_lock.acquire()
                    relay_fee_record[dk] = ZERO_FEE
                    fee_record_lock.release()

                    start_block_lock.acquire()
                    start_block_record[network] = block_number + 1
                    start_block_lock.release()

                    portal_vaa_q.put((app_id, call_type, vaa, sequence, network))

                    data[dk] = vaa

                    local_logger.info(f"Have a {call_name} transaction from {network}, sequence: {sequence}")
        except Exception as e:
            local_logger.error(f"Error: {e}")
            traceback.print_exc()
        time.sleep(1)


def pool_withdraw_watcher():
    data = BridgeDict("pool_withdraw_vaa.json")
    local_logger = logger.getChild("[pool_withdraw_watcher]")
    local_logger.info("Start to read withdraw vaa ^-^")

    sui_network = sui_project.network
    while True:
        try:
            relay_events = dola_sui_init.query_core_relay_event()

            for event in relay_events:
                fields = event['parsedJson']

                source_chain_id = fields['source_chain_id']
                srouce_chain_nonce = fields['source_chain_nonce']

                dk = f"pool_withdraw_{source_chain_id}_{str(srouce_chain_nonce)}"
                if dk not in data:
                    call_type = fields["call_type"]
                    call_name = get_call_name(1, int(call_type))
                    src_network = get_dola_network(source_chain_id)
                    sequence = fields['sequence']
                    vaa = get_signed_vaa_by_wormhole(WORMHOLE_EMITTER_ADDRESS[sui_network], sequence, sui_network)

                    dst_pool = fields['dst_pool']
                    dst_chain_id = int(dst_pool['dola_chain_id'])
                    dst_pool_address = f"0x{bytes(dst_pool['dola_address']).hex()}"

                    if dst_chain_id == 0:
                        sui_withdraw_q.put((vaa, source_chain_id, srouce_chain_nonce, call_type, dst_pool_address))
                        local_logger.info(
                            f"Have a {call_name} from {src_network} to sui, nonce: {srouce_chain_nonce}")
                    elif dst_chain_id == 1:
                        aptos_withdraw_q.put((vaa, source_chain_id, srouce_chain_nonce, call_type, dst_pool_address))
                        local_logger.info(
                            f"Have a {call_name} from {src_network} to aptos, nonce: {srouce_chain_nonce}")
                    else:
                        eth_withdraw_q.put((vaa, source_chain_id, srouce_chain_nonce, call_type, dst_chain_id))
                        local_logger.info(
                            f"Have a {call_name} from {src_network} to {get_dola_network(dst_chain_id)}, nonce: {srouce_chain_nonce}")
                    data[dk] = vaa
        except Exception as e:
            local_logger.error(f"Error: {e}")
        time.sleep(3)


def sui_core_executor():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    data = BridgeDict("sui_core_executed_vaa.json")
    local_logger = logger.getChild("[sui_core_executor]")
    local_logger.info("Start to relay pool vaa ^-^")
    while True:
        try:
            (app_id, call_type, vaa, nonce, chain) = portal_vaa_q.get()

            call_name = get_call_name(app_id, call_type)
            dk = f"{chain}_portal_{call_name}_{nonce}"

            # compensate unfinished transaction
            if dk not in relay_fee_record:
                fee_record_lock.acquire()
                relay_fee_record[dk] = ZERO_FEE
                fee_record_lock.release()

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]
                relay_fee = get_fee_amount(relay_fee_value)

                # Because the rpc of sui test network often times out, it is impossible
                # to judge whether the transaction is executed successfully or not, so
                # the default transaction execution is successful.
                data[dk] = vaa

                rotate_accounts()
                gas, executed = execute_sui_core(app_id, call_type, vaa, relay_fee)

                gas_amount = gas
                if executed:
                    if call_name in ["withdraw", "borrow"]:
                        relay_fee_record[dk] = get_fee_value(relay_fee - gas_amount)
                    else:
                        finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                     "consumed_fee": get_fee_value(gas_amount)}
                        del relay_fee_record[dk]

                        gas_price = int(sui_project.client.suix_getReferenceGasPrice())
                        action_gas_record[f"sui_{call_name}"] = int(gas_amount / gas_price)
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
            traceback.print_exc()
            local_logger.error(f"Execute sui core fail\n {e}")


def sui_pool_executor():
    data = BridgeDict("sui_pool_executed_vaa.json")
    local_logger = logger.getChild("[sui_pool_executor]")
    local_logger.info("Start to relay sui withdraw vaa ^-^")

    while True:
        try:
            (vaa, source_chain_id, source_nonce, call_type, token_name) = sui_withdraw_q.get()
            chain = get_dola_network(source_chain_id)
            call_name = get_call_name(1, int(call_type))
            dk = f"{chain}_portal_{call_name}_{source_nonce}"

            # todo: removed after fixing sui_watcher
            if dk not in relay_fee_record:
                fee_record_lock.acquire()
                relay_fee_record[dk] = ZERO_FEE
                fee_record_lock.release()

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]

                available_gas_amount = get_fee_amount(relay_fee_value, 'sui')

                rotate_accounts()

                gas_used, executed = dola_sui_lending.pool_withdraw(vaa, token_name, available_gas_amount)

                tx_gas_amount = gas_used
                if executed:
                    finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                 "consumed_fee": get_fee_value(tx_gas_amount)}

                    del relay_fee_record[dk]
                    gas_price = int(sui_project.client.suix_getReferenceGasPrice())
                    action_gas_record[f"sui_{call_name}"] = int(tx_gas_amount / gas_price)

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
            traceback.print_exc()
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
                fee_record_lock.acquire()
                relay_fee_record[dk] = ZERO_FEE
                fee_record_lock.release()

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]
                available_gas_amount = get_fee_amount(relay_fee_value, 'apt')

                gas_used = aptos_omnipool.wormhole_adapter_pool.receive_withdraw.simulate(
                    vaa,
                    ty_args=[token_name],
                    return_types="gas"
                )
                gas_price = aptos_omnipool.estimate_gas_price()
                tx_gas_amount = int(gas_used) * int(gas_price)
                if available_gas_amount > tx_gas_amount:
                    aptos_omnipool.wormhole_adapter_pool.receive_withdraw(
                        vaa,
                        ty_args=[token_name]
                    )
                    finished_transactions[dk] = {"relay_fee": relay_fee_record[dk],
                                                 "consumed_fee": get_fee_value(tx_gas_amount)}
                    del relay_fee_record[dk]
                    action_gas_record[f"aptos_{call_name}"] = int(gas_used)
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
            traceback.print_exc()
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

            ethereum_wormhole_bridge = dola_ethereum_load.wormhole_adapter_pool_package(network)
            ethereum_account = dola_ethereum_sdk.get_account()
            local_logger.info(f"Ethereum account: {ethereum_account.address}")
            call_name = get_call_name(1, int(call_type))
            source_chain = get_dola_network(source_chain_id)
            dk = f"{source_chain}_portal_{call_name}_{source_nonce}"

            # todo: removed after fixing sui_watcher
            if dk not in relay_fee_record:
                fee_record_lock.acquire()
                relay_fee_record[dk] = ZERO_FEE
                fee_record_lock.release()

            if dk not in data:
                relay_fee_value = relay_fee_record[dk]
                available_gas_amount = get_fee_amount(relay_fee_value, get_gas_token(network))

                gas_price = brownie.network.gas_price()
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
            traceback.print_exc()
            local_logger.error(f"Execute eth pool withdraw fail\n {e}")


def compensate_unfinished_transaction():
    # todo: Monitor Wormhole vaa whether it has been executed for compensation.
    local_logger = logger.getChild("[compensate_unfinished_transaction]")
    local_logger.info("Start to compensate pool vaa ^-^")
    while True:
        # Check for pool_vaa that is not executed

        # Sui has pool_vaa only when performing liquidation.
        # sui_pool_vaa = BridgeDict("sui_pool_vaa.json")

        aptos_pool_vaa = BridgeDict("aptos_pool_vaa.json")
        polygon_pool_vaa = BridgeDict("polygon-test_pool_vaa.json")
        bsc_pool_vaa = BridgeDict("bsc-test_pool_vaa.json")
        polygon_zk_pool_vaa = BridgeDict("polygon-zk-test_pool_vaa.json")

        sui_core_executed_vaa = BridgeDict("sui_core_executed_vaa.json")

        unfinished_tx = aptos_pool_vaa.keys() | polygon_pool_vaa.keys() | polygon_zk_pool_vaa.keys() | bsc_pool_vaa.keys() - sui_core_executed_vaa.keys()

        for key in list(unfinished_tx)[:10]:
            data = key.split('_')
            network = data[0]
            nonce = data[-1]
            local_logger.info(f"Compensate {network} pool vaa, nonce: {nonce}")
            if network == 'aptos':
                portal_vaa_q.put((aptos_pool_vaa[key], nonce, 'aptos'))
            elif network == 'polygon-test':
                portal_vaa_q.put((polygon_pool_vaa[key], nonce, 'polygon-test'))
            elif network == 'polygon-zk-test':
                portal_vaa_q.put((polygon_zk_pool_vaa[key], nonce, 'polygon-zk-test'))
            elif network == 'bsc-test':
                portal_vaa_q.put((bsc_pool_vaa[key], nonce, 'bsc-test'))
            else:
                local_logger.warning(f"Unknown network: {network}")

        time.sleep(60)
    # todo: No handling fee is charged for the time being, so the transaction compensated
    #       for insufficient handling fee does not exist for the time being.
    # unfinished_transactions.read_data()
    # # Priority compensation for more relayer fee
    # keys = sorted(unfinished_transactions, reverse=True, key=lambda i: unfinished_transactions[i]['relay_fee'])
    # # todo: Calculate relay_fee using Action Gas to ensure that the compensated
    # #       transaction relay_fee is enough to put in the queue.
    #
    # for k in keys:
    #     if "core" in k:
    #         dk = str(k).removeprefix('core_')
    #         portal_data = unfinished_transactions[k]
    #         relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
    #
    #         portal_vaa_q.put((portal_data['vaa'], portal_data['nonce'], portal_data['chain']))
    #     elif "sui_pool" in k:
    #         dk = str(k).removeprefix('sui_pool_')
    #         withdraw_data = unfinished_transactions[k]
    #         relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
    #         sui_withdraw_q.put((withdraw_data['vaa'],
    #                             withdraw_data['source_chain_id'],
    #                             withdraw_data['source_nonce'],
    #                             withdraw_data['call_type'],
    #                             withdraw_data['token_name']))
    #     elif "aptos_pool" in k:
    #         dk = str(k).removeprefix('aptos_pool_')
    #         withdraw_data = unfinished_transactions[k]
    #         relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
    #         aptos_withdraw_q.put((withdraw_data['vaa'],
    #                               withdraw_data['source_chain_id'],
    #                               withdraw_data['source_nonce'],
    #                               withdraw_data['call_type'],
    #                               withdraw_data['token_name']))
    #     else:
    #         dk = str(k).split('_')[1]
    #         withdraw_data = unfinished_transactions[k]
    #         relay_fee_record[dk] = unfinished_transactions[k]['relay_fee']
    #         eth_withdraw_q.put((withdraw_data['vaa'],
    #                             withdraw_data['source_chain_id'],
    #                             withdraw_data['source_nonce'],
    #                             withdraw_data['call_type'],
    #                             withdraw_data['dola_chain_id']))


def sui_vaa_payload(vaa):
    wormhole = dola_sui_load.wormhole_package()

    result = sui_project.batch_transaction_inspect(
        actual_params=[
            sui_project.network_config['objects']['WormholeState'],
            list(bytes.fromhex(vaa.replace("0x", ""))),
            dola_sui_init.clock()
        ],
        transactions=[
            [
                wormhole.vaa.parse_and_verify,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                ],
                []
            ],
            [
                wormhole.vaa.payload,
                [
                    Argument("Result", U16(0))
                ],
                []
            ]
        ]
    )

    pprint(result)


NET_TO_WORMHOLE_CHAINID = {
    # mainnet
    "mainnet": 2,
    "bsc-main": 4,
    "polygon-main": 5,
    "avax-main": 6,
    "optimism-main": 24,
    "arbitrum-main": 23,
    "aptos-mainnet": 22,
    "sui-mainnet": 21,
    # testnet
    "goerli": 2,
    "bsc-test": 4,
    "polygon-test": 5,
    "avax-test": 6,
    "optimism-test": 24,
    "arbitrum-test": 23,
    "aptos-testnet": 22,
    "sui-testnet": 21,
}

WORMHOLE_EMITTER_ADDRESS = {
    # mainnet
    "polygon-main": "0x5af12a3FBeeb89C21699ACeD9615848A3c2D4f4E",
    "sui-mainnet": "0xdef592d077e939fdf83f3a06cbd2b701d16d87fe255bfc834b851d70f062e95d",
    # testnet
    "polygon-test": "0xE5230B6bA30Ca157988271DC1F3da25Da544Dd3c",
    "sui-testnet": "0x9031f04d97adacea16a923f20b9348738a496fb98f9649b93f68406bafb2437e",
}


@retry(stop_max_attempt_number=5, wait_random_min=1000, wait_random_max=10000)
def get_signed_vaa_by_wormhole(
        emitter: str,
        sequence: int,
        src_net: str = None
):
    """
    Get signed vaa
    :param emitter:
    :param src_net:
    :param sequence:
    :return: dict
        {'vaaBytes': 'AQAAAAEOAGUI...'}
    """
    wormhole_url = sui_project.network_config['wormhole_url']
    emitter_address = dola_sui_init.format_emitter_address(emitter)
    emitter_chainid = NET_TO_WORMHOLE_CHAINID[src_net]

    url = f"{wormhole_url}/v1/signed_vaa/{emitter_chainid}/{emitter_address}/{sequence}"
    response = requests.get(url)

    if 'vaaBytes' not in response.json():
        raise ValueError(f"Get {src_net} signed vaa failed: {response.text}")

    vaa_bytes = response.json()['vaaBytes']
    vaa = base64.b64decode(vaa_bytes).hex()
    return f"0x{vaa}"


def get_signed_vaa(
        sequence: int,
        src_wormhole_id: int = None,
        url: str = None
):
    if url is None:
        url = "http://wormhole-testnet.sherpax.io"
    if src_wormhole_id is None:
        data = {
            "method": "GetSignedVAA",
            "params": [
                str(sequence),
            ]
        }
    else:
        data = {
            "method": "GetSignedVAA",
            "params": [
                str(sequence),
                src_wormhole_id,
            ]
        }
    headers = {'content-type': 'application/json'}
    response = requests.post(url, data=json.dumps(data), headers=headers)
    return response.json()


def run_aptos_relayer():
    dola_aptos_sdk.set_dola_project_path(Path("../.."))
    pt = ThreadExecutor(executor=2)

    pt.run([
        aptos_portal_watcher,
        aptos_pool_executor
    ])


def run_sui_relayer():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    pt = ThreadExecutor(executor=2)

    pt.run([
        pool_withdraw_watcher,
        sui_pool_executor
    ])


def main():
    pt = ProcessExecutor(executor=2)

    pt.run([
        # run_sui_relayer,
        # run_aptos_relayer,
        sui_core_executor,
        functools.partial(eth_portal_watcher, "polygon-main"),
        # functools.partial(eth_portal_watcher, "arbitrum-test"),
        # eth_pool_executor,
        # compensate_unfinished_transaction
    ])


if __name__ == "__main__":
    main()
