import asyncio.exceptions
import base64
import datetime
import functools
import json
import logging
import time
import traceback
from hmac import compare_digest
from multiprocessing import Manager
from pathlib import Path

import brownie
import ccxt
import requests
from dotenv import dotenv_values
from gql import gql
from gql.client import log as gql_client_logs
from gql.transport.aiohttp import log as gql_logs
from pymongo import MongoClient
from retrying import retry
from sui_brownie.parallelism import ProcessExecutor

import config
import dola_ethereum_sdk
import dola_ethereum_sdk.init as dola_ethereum_init
import dola_ethereum_sdk.load as dola_ethereum_load
import dola_monitor
import dola_sui_sdk
import dola_sui_sdk.init as dola_sui_init
import dola_sui_sdk.lending as dola_sui_lending
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


def init_logger():
    global logger
    FORMAT = '%(asctime)s - %(funcName)s - %(levelname)s - %(name)s: %(message)s'
    logger = logging.getLogger()
    logger.setLevel("INFO")
    # create console handler with a higher log level
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)

    ch.setFormatter(ColorFormatter(FORMAT))

    logger.addHandler(ch)

    gql_client_logs.setLevel(logging.WARNING)
    gql_logs.setLevel(logging.WARNING)
    return logger


def init_markets():
    global kucoin
    kucoin = ccxt.kucoin()
    kucoin.load_markets()


def fix_requests_ssl():
    requests.packages.urllib3.util.ssl_.DEFAULT_CIPHERS = 'ALL'


@retry
def get_token_price(token):
    symbol = config.NATIVE_TOKEN_NAME_TO_KUCOIN_SYMBOL[token]
    return float(kucoin.fetch_ticker(symbol)['close'])


def get_token_decimal(token):
    return config.NATIVE_TOKEN_NAME_TO_DECIMAL[token]


def get_fee_value(amount, token='sui'):
    price = get_token_price(token)
    decimal = get_token_decimal(token)
    return price * amount / pow(10, decimal)


def get_fee_amount(value, token='sui'):
    price = get_token_price(token)
    decimal = get_token_decimal(token)
    return int(value / price * pow(10, decimal))


def get_call_name(app_id: int, call_type: int):
    return config.CALL_TYPE_TO_CALL_NAME[app_id][call_type]


def get_dola_network(dola_chain_id: int):
    return config.DOLA_CHAIN_ID_TO_NETWORK[dola_chain_id]


def get_gas_token(network='polygon-test'):
    return config.NETWORK_TO_NATIVE_TOKEN[network]


def execute_sui_core(call_name, vaa, relay_fee, fee_rate=0.8):
    gas = 0
    executed = False
    status = "Unknown"
    feed_nums = 0
    digest = ""
    if call_name == "binding":
        gas, executed, status, digest = dola_sui_lending.core_binding(vaa, relay_fee, fee_rate)
    elif call_name == "unbinding":
        gas, executed, status, digest = dola_sui_lending.core_unbinding(vaa, relay_fee, fee_rate)
    elif call_name == "supply":
        gas, executed, status, digest = dola_sui_lending.core_supply(vaa, relay_fee, fee_rate)
    elif call_name == "withdraw":
        gas, executed, status, feed_nums, digest = dola_sui_lending.core_withdraw(vaa, relay_fee, fee_rate)
    elif call_name == "borrow":
        gas, executed, status, feed_nums, digest = dola_sui_lending.core_borrow(vaa, relay_fee, fee_rate)
    elif call_name == "repay":
        gas, executed, status, digest = dola_sui_lending.core_repay(vaa, relay_fee, fee_rate)
    elif call_name == "liquidate":
        gas, executed, status, feed_nums, digest = dola_sui_lending.core_liquidate(vaa, relay_fee, fee_rate)
    elif call_name == "as_collateral":
        gas, executed, status, digest = dola_sui_lending.core_as_collateral(vaa, relay_fee, fee_rate)
    elif call_name == "cancel_as_collateral":
        gas, executed, status, feed_nums, digest = dola_sui_lending.core_cancel_as_collateral(
            vaa, relay_fee, fee_rate)
    return gas, executed, status, feed_nums, digest


class RelayRecord:

    def __init__(self):
        db = mongodb()
        self.db = db['RelayRecord']

    def add_other_record(self, src_chain_id, src_tx_id, nonce, call_name, block_number, sequence, vaa, relay_fee,
                         start_time):
        record = {
            "src_chain_id": src_chain_id,
            "src_tx_id": src_tx_id,
            "nonce": nonce,
            "call_name": call_name,
            "block_number": block_number,
            "sequence": sequence,
            "vaa": vaa,
            "relay_fee": relay_fee,
            "core_tx_id": "",
            "core_costed_fee": 0,
            "status": "false",
            "reason": "Unknown",
            "start_time": start_time,
            "end_time": "",
        }
        self.db.insert_one(record)

    def add_withdraw_record(self, src_chain_id, src_tx_id, nonce, call_name, block_number, sequence, vaa, relay_fee,
                            start_time, core_tx_id="", core_costed_fee=0, withdraw_chain_id="",
                            withdraw_tx_id="",
                            withdraw_sequence=0, withdraw_vaa="", withdraw_pool="", withdraw_costed_fee=0,
                            status='false'):
        record = {
            "src_chain_id": src_chain_id,
            "src_tx_id": src_tx_id,
            "nonce": nonce,
            "call_name": call_name,
            "block_number": block_number,
            "sequence": sequence,
            "vaa": vaa,
            "relay_fee": relay_fee,
            "core_tx_id": core_tx_id,
            "core_costed_fee": core_costed_fee,
            "withdraw_chain_id": withdraw_chain_id,
            "withdraw_tx_id": withdraw_tx_id,
            "withdraw_sequence": withdraw_sequence,
            "withdraw_vaa": withdraw_vaa,
            "withdraw_pool": withdraw_pool,
            "withdraw_costed_fee": withdraw_costed_fee,
            "status": status,
            "reason": "Unknown",
            "start_time": start_time,
            "end_time": "",
        }
        self.db.insert_one(record)

    def add_wait_record(self, src_chain_id, src_tx_id, nonce, sequence, block_number, relay_fee_value, date):
        record = {
            'src_chain_id': src_chain_id,
            'src_tx_id': src_tx_id,
            'nonce': nonce,
            'sequence': sequence,
            'block_number': block_number,
            'relay_fee': relay_fee_value,
            'status': 'waitForVaa',
            'start_time': date,
            'end_time': "",
        }
        self.db.insert_one(record)

    def update_record(self, filter, update):
        self.db.update_one(filter, update)

    def find_one(self, filter):
        return self.db.find_one(filter)

    def find(self, filter):
        return self.db.find(filter)


class GasRecord:

    def __init__(self):
        db = mongodb()
        self.db = db['GasRecord']

    def add_gas_record(self, src_chain_id, nonce, dst_chain_id, call_name, core_gas=0, feed_nums=0):
        record = {
            'src_chain_id': src_chain_id,
            'nonce': nonce,
            'dst_chain_id': dst_chain_id,
            'call_name': call_name,
            'core_gas': core_gas,
            'withdraw_gas': 0,
            'feed_nums': feed_nums
        }
        self.db.insert_one(record)

    def update_record(self, filter, update):
        self.db.update_one(filter, update)

    def find(self, filter):
        return self.db.find(filter)


def sui_portal_watcher(health):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    local_logger = logger.getChild("[sui_portal_watcher]")
    local_logger.info("Start to watch sui portal ^-^")

    relay_record = RelayRecord()

    src_chain_id = 0

    sui_network = sui_project.network

    # query latest tx
    result = list(relay_record.find({'src_chain_id': src_chain_id}).sort("start_time", -1).limit(1))
    latest_sui_tx = result[0]['src_tx_id'] if 'src_tx_id' in result[0] else ""

    while True:
        try:
            prev_sui_tx = latest_sui_tx
            result = list(relay_record.find({'src_chain_id': src_chain_id}).sort("start_time", -1).limit(1))
            latest_sui_tx = result[0]['src_tx_id'] if 'src_tx_id' in result[0] else prev_sui_tx
            relay_events = dola_sui_init.query_pool_relay_event(latest_sui_tx)

            for event in relay_events:
                fields = event['parsedJson']

                app_id = fields["app_id"]
                call_type = fields["call_type"]
                sequence = int(fields['sequence'])
                call_name = get_call_name(app_id, int(call_type))
                nonce = int(fields['nonce'])

                if not health.value:
                    local_logger.error(f"src_chain_nonce: {nonce}, sequence: {sequence}")
                    raise ValueError("Health check failed, sui portal watcher blocked")

                if not relay_record.find_one({'src_chain_id': src_chain_id, 'nonce': nonce, 'sequence': sequence}):
                    relay_fee_amount = int(fields['fee_amount'])
                    relay_fee_value = get_fee_value(relay_fee_amount, 'sui')

                    timestamp_ms = int(event['timestampMs'])
                    timestamp = timestamp_ms // 1000
                    start_time = str(datetime.datetime.utcfromtimestamp(timestamp))
                    src_tx_id = event['id']['txDigest']

                    emitter = config.NET_TO_WORMHOLE_EMITTER[f'{sui_network}-pool']
                    vaa = get_signed_vaa_by_wormhole(emitter, sequence, sui_network)

                    payload = dola_sui_lending.parse_vaa(vaa)

                    payload_on_chain = dola_sui_lending.get_sui_wormhole_payload(src_tx_id)

                    if not check_payload_hash(str(payload), str(payload_on_chain)):
                        local_logger.error(f'payload: {payload}')
                        local_logger.error(f'payload_on_chain: {payload_on_chain}')
                        raise ValueError("The data may have been manipulated!")

                    if call_name in ['withdraw', 'borrow']:
                        relay_record.add_withdraw_record(src_chain_id, src_tx_id, nonce, call_name, timestamp_ms,
                                                         sequence, vaa, relay_fee_value, start_time)
                    else:
                        relay_record.add_other_record(src_chain_id, src_tx_id, nonce, call_name, timestamp_ms,
                                                      sequence, vaa, relay_fee_value, start_time)

                    local_logger.info(
                        f"Have a {call_name} transaction from sui, nonce: {nonce}")
        except Exception as e:
            local_logger.error(f"Error: {e}")
        time.sleep(3)


def wormhole_vaa_guardian(network="polygon-test"):
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(network)

    local_logger = logger.getChild(f"[{network}_wormhole_vaa_guardian]")
    local_logger.info("Start to wait wormhole vaa ^-^")

    relay_record = RelayRecord()

    src_chain_id = config.NET_TO_WORMHOLE_CHAIN_ID[network]
    emitter_address = dola_ethereum_load.wormhole_adapter_pool_package(network).address
    wormhole = dola_ethereum_load.womrhole_package(network)

    while True:
        try:
            wait_vaa_txs = list(relay_record.find({'status': 'waitForVaa', 'src_chain_id': src_chain_id}).sort(
                "block_number", 1))
        except Exception as e:
            local_logger.warning(f"relay record find failed! {e}")
            continue

        for tx in wait_vaa_txs:
            try:
                nonce = tx['nonce']
                sequence = tx['sequence']
                block_number = tx['block_number']

                vaa = get_signed_vaa_by_wormhole(
                    emitter_address, sequence, network)

                vm = wormhole.parseVM(vaa)
                # parse payload
                payload = list(vm)[7]

                # check that cross-chain data is consistent with on-chain data
                payload_on_chain = dola_ethereum_init.get_payload_from_chain(tx['src_tx_id'])
                if not check_payload_hash(str(payload), str(payload_on_chain)):
                    local_logger.error(f'payload: {payload}')
                    local_logger.error(f'payload_on_chain: {payload_on_chain}')
                    raise ValueError("The data may have been manipulated!")

                app_id = payload[1]
                call_type = payload[-1]
                call_name = get_call_name(app_id, call_type)

                relay_fee = tx['relay_fee']

                if call_name in ['withdraw', 'borrow']:
                    relay_record.add_withdraw_record(src_chain_id, tx['src_tx_id'], nonce, call_name, block_number,
                                                     sequence, vaa,
                                                     relay_fee, tx['start_time'])
                else:
                    relay_record.add_other_record(src_chain_id, tx['src_tx_id'], nonce, call_name, block_number,
                                                  sequence, vaa,
                                                  relay_fee, tx['start_time'])

                current_timestamp = int(time.time())
                date = str(datetime.datetime.fromtimestamp(current_timestamp))
                relay_record.update_record({'status': 'waitForVaa', 'src_chain_id': src_chain_id, 'nonce': nonce},
                                           {'$set': {'status': 'dropped', 'end_time': date}})
                local_logger.info(
                    f"Have a {call_name} transaction from {network}, sequence: {nonce}")
            except Exception as e:
                local_logger.warning(f"Error: {e}")
        time.sleep(5)


def eth_portal_watcher(health, network="polygon-test"):
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(network)

    local_logger = logger.getChild(f"[{network}_portal_watcher]")
    local_logger.info(f"Start to read {network} pool vaa ^-^")

    relay_record = RelayRecord()

    src_chain_id = config.NET_TO_WORMHOLE_CHAIN_ID[network]
    wormhole = dola_ethereum_load.womrhole_package(network)
    emitter_address = dola_ethereum_load.wormhole_adapter_pool_package(network).address
    lending_portal = dola_ethereum_load.lending_portal_package(network).address
    system_portal = dola_ethereum_load.system_portal_package(network).address

    external_endpoint = brownie.web3.provider.endpoint_uri

    w3_client = dola_ethereum_init.fallback_endpoints_web3(network, [external_endpoint])

    # graphql_url = dola_ethereum_init.graphql_url(network)
    # transport = AIOHTTPTransport(url=graphql_url)
    #
    # # Create a GraphQL client using the defined transport
    # client = Client(transport=transport, fetch_schema_from_transport=True)

    # query latest block number
    result = list(relay_record.find({'src_chain_id': src_chain_id}).sort("block_number", -1).limit(1))
    latest_relay_block_number = result[0]['block_number'] if result else 0

    while True:
        try:
            result = list(relay_record.find({'src_chain_id': src_chain_id}).sort("block_number", -1).limit(1))
            latest_relay_block_number = result[0]['block_number'] if result else latest_relay_block_number

            if network == 'base-main':
                latest_relay_block_number = w3_client.eth.get_block_number() - 500

            # query relay events from latest relay block number + 1 to actual latest block number
            relay_events = dola_ethereum_init.query_relay_event_by_get_logs(w3_client, lending_portal, system_portal,
                                                                            latest_relay_block_number)

            for event in relay_events:
                nonce = int(event['nonce'])
                sequence = int(event['sequence'])

                if not health.value:
                    local_logger.error(f"src_chain_nonce: {nonce}, sequence: {sequence}")
                    raise ValueError(f"health check failed, {network} portal watcher blocked")

                # check if the event has been recorded
                if not list(relay_record.find(
                        {
                            'src_chain_id': src_chain_id,
                            'nonce': nonce,
                            "sequence": sequence,
                        }
                )):
                    block_number = int(event['blockNumber'])
                    src_tx_id = event['transactionHash']
                    timestamp = int(event['blockTimestamp'])

                    app_id = int(event['appId'])
                    call_type = int(event['callType'])
                    call_name = get_call_name(app_id, call_type)
                    relay_fee_amount = int(event['feeAmount'])
                    start_time = str(datetime.datetime.utcfromtimestamp(timestamp))

                    gas_token = get_gas_token(network)
                    relay_fee_value = get_fee_value(relay_fee_amount, gas_token)

                    # get vaa
                    try:
                        vaa = get_signed_vaa_by_wormhole(
                            emitter_address, sequence, network)
                    except Exception as e:
                        relay_record.add_wait_record(src_chain_id, src_tx_id, nonce, sequence, block_number,
                                                     relay_fee_value,
                                                     start_time)
                        local_logger.warning(f"Warning: {e}")
                        continue
                    # parse vaa

                    vm = wormhole.parseVM(vaa)
                    # parse payload
                    payload = list(vm)[7]

                    # check that cross-chain data is consistent with on-chain data
                    payload_on_chain = dola_ethereum_init.get_payload_from_chain(src_tx_id)
                    if not check_payload_hash(str(payload), str(payload_on_chain)):
                        local_logger.error(f'payload: {payload}')
                        local_logger.error(f'payload_on_chain: {payload_on_chain}')
                        raise ValueError("The data may have been manipulated!")

                    if call_name in ['withdraw', 'borrow']:
                        relay_record.add_withdraw_record(src_chain_id, src_tx_id, nonce, call_name, block_number,
                                                         sequence, vaa, relay_fee_value, start_time)
                    else:
                        relay_record.add_other_record(src_chain_id, src_tx_id, nonce, call_name, block_number,
                                                      sequence, vaa, relay_fee_value, start_time)

                    local_logger.info(
                        f"Have a {call_name} transaction from {network}, sequence: {sequence}")
        except asyncio.exceptions.TimeoutError:
            local_logger.warning("GraphQL request timeout")
        except Exception as e:
            local_logger.error(f"Error: {e}")
        finally:
            time.sleep(2)


def pool_withdraw_watcher(health):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    local_logger = logger.getChild("[pool_withdraw_watcher]")
    local_logger.info("Start to read withdraw vaa ^-^")

    relay_record = RelayRecord()

    sui_network = sui_project.network

    # query latest core tx
    result = list(
        relay_record.find({"withdraw_tx_id": {"$exists": 1}, 'core_tx_id': {"$ne": ""}, 'status': 'success'})
        .sort("start_time", -1).limit(1))
    latest_sui_tx = result[0]['core_tx_id']

    while True:
        try:
            prev_sui_tx = latest_sui_tx
            result = list(
                relay_record.find({"withdraw_tx_id": {"$exists": 1}, 'core_tx_id': {"$ne": ""}, 'status': 'success'})
                .sort("start_time", -1).limit(1))
            latest_sui_tx = result[0]['core_tx_id'] if result else prev_sui_tx
            relay_events = dola_sui_init.query_core_relay_event(latest_sui_tx)

            for event in relay_events:
                fields = event['parsedJson']

                source_chain_id = int(fields['source_chain_id'])
                source_chain_nonce = int(fields['source_chain_nonce'])

                if not health.value:
                    local_logger.error(
                        f"Processing src_chain_id: {source_chain_id}, source_chain_nonce: {source_chain_nonce}")
                    raise ValueError("health check failed, withdraw watcher blocked")

                if relay_record.find_one(
                        {'src_chain_id': source_chain_id, 'nonce': source_chain_nonce, 'status': 'waitForWithdraw'}):
                    call_type = fields["call_type"]
                    call_name = get_call_name(1, int(call_type))
                    src_network = get_dola_network(source_chain_id)
                    sequence = int(fields['sequence'])

                    emitter = config.NET_TO_WORMHOLE_EMITTER[sui_network]
                    vaa = get_signed_vaa_by_wormhole(emitter, sequence, sui_network)

                    # check that cross-chain data is consistent with on-chain data
                    payload = dola_sui_lending.parse_vaa(vaa)

                    payload_on_chain = dola_sui_lending.get_sui_wormhole_payload(event['id']['txDigest'])

                    if not check_payload_hash(str(payload), str(payload_on_chain)):
                        local_logger.error(f'payload: {payload}')
                        local_logger.error(f'payload_on_chain: {payload_on_chain}')
                        raise ValueError("The data may have been manipulated!")

                    dst_pool = fields['dst_pool']
                    dst_chain_id = int(dst_pool['dola_chain_id'])
                    if dst_chain_id == 0:
                        dst_pool_address = f"0x{bytes(dst_pool['dola_address']).decode()}"
                    else:
                        dst_pool_address = f"0x{bytes(dst_pool['dola_address']).hex()}"

                    relay_record.update_record({'src_chain_id': source_chain_id, 'nonce': source_chain_nonce},
                                               {"$set": {'status': 'withdraw', 'withdraw_vaa': vaa,
                                                         'withdraw_chain_id': dst_chain_id,
                                                         'withdraw_sequence': sequence,
                                                         'withdraw_pool': dst_pool_address}})

                    local_logger.info(
                        f"Have a {call_name} from {src_network} to {get_dola_network(dst_chain_id)}, nonce: {source_chain_nonce}")
        except Exception as e:
            traceback.print_exc()
            local_logger.error(f"Error: {e}")
        time.sleep(1)


def sui_core_executor(relayer_account, divisor=1, remainder=0):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    sui_project.active_account(relayer_account)

    local_logger = logger.getChild(f"[sui_core_executor_{remainder}]")
    local_logger.info("Start to relay pool vaa ^-^")

    relay_record = RelayRecord()
    gas_record = GasRecord()

    while True:
        try:
            relay_transactions = relay_record.find({"status": "false", "nonce": {"$mod": [divisor, remainder]}})
        except Exception as e:
            local_logger.warning(f"relay record find failed! {e}")
            continue

        for tx in relay_transactions:
            try:
                relay_fee_value = tx['relay_fee']
                relay_fee = get_fee_amount(relay_fee_value)
                call_name = tx['call_name']

                # check relayer balance
                if sui_total_balance() < int(1e9):
                    local_logger.warning(
                        f"Relayer balance is not enough, need {relay_fee_value} sui")
                    time.sleep(5)
                    continue

                # If no gas record exists, relay once for free.
                fee_rate = 0
                if not list(gas_record.find(
                        {'src_chain_id': tx['src_chain_id'], 'dst_chain_id': 0, 'call_name': call_name})):
                    fee_rate = 0

                gas, executed, status, feed_nums, digest = execute_sui_core(
                    call_name, tx['vaa'], relay_fee, fee_rate)

                # Relay not existent feed_num tx for free.
                if not executed and not list(gas_record.find(
                        {'src_chain_id': tx['src_chain_id'], 'dst_chain_id': 0, 'call_name': call_name,
                         'feed_nums': feed_nums})):
                    fee_rate = 0
                    gas, executed, status, feed_nums, digest = execute_sui_core(
                        call_name, tx['vaa'], relay_fee, fee_rate)

                gas_price = int(
                    sui_project.client.suix_getReferenceGasPrice())
                gas_limit = int(gas / gas_price)

                gas_record.add_gas_record(tx['src_chain_id'], tx['nonce'], 0, call_name, gas_limit, feed_nums)
                core_costed_fee = get_fee_value(gas, 'sui')

                if executed and status == 'success':
                    relay_fee_value = get_fee_value(relay_fee, 'sui')

                    timestamp = int(time.time())
                    date = str(datetime.datetime.utcfromtimestamp(timestamp))
                    if call_name in ["withdraw", "borrow"]:
                        relay_record.update_record({'vaa': tx['vaa']},
                                                   {"$set": {'relay_fee': relay_fee_value,
                                                             'status': 'waitForWithdraw',
                                                             'end_time': date,
                                                             'core_tx_id': digest,
                                                             'core_costed_fee': core_costed_fee}})
                    else:
                        relay_record.update_record({'vaa': tx['vaa']},
                                                   {"$set": {'relay_fee': relay_fee_value, 'status': 'success',
                                                             'core_tx_id': digest,
                                                             'core_costed_fee': core_costed_fee,
                                                             'end_time': date}})
                    local_logger.info("Execute sui core success! ")
                    local_logger.info(f"relay fee: {relay_fee_value} USD, consumed fee: {core_costed_fee} USD")
                else:
                    relay_record.update_record({'vaa': tx['vaa']},
                                               {"$set": {'status': 'fail', 'reason': status}})
                    local_logger.warning("Execute sui core fail! ")
                    local_logger.warning(f"relay fee: {relay_fee_value} USD, consumed fee: {core_costed_fee} USD")
                    local_logger.warning(f"status: {status}")
            except AssertionError as e:
                # status = eval(str(e))
                relay_record.update_record({'vaa': tx['vaa']},
                                           {"$set": {'status': 'fail', 'reason': str(e)}})
                local_logger.warning("Execute sui core fail! ")
                local_logger.warning(f"status: {str(e)}")
            except Exception as e:
                traceback.print_exc()
                local_logger.error(f"Execute sui core fail\n {e}")
        time.sleep(1)


def sui_pool_executor(relayer_account):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    sui_project.active_account(relayer_account)

    local_logger = logger.getChild("[sui_pool_executor]")
    local_logger.info("Start to relay sui withdraw vaa ^-^")

    relay_record = RelayRecord()
    gas_record = GasRecord()

    while True:
        try:
            relay_transactions = relay_record.find(
                {"status": "withdraw", "withdraw_chain_id": 0})
        except Exception as e:
            local_logger.warning(f"relay record find failed! {e}")
            continue

        for withdraw_tx in relay_transactions:
            try:
                core_costed_fee = (
                    withdraw_tx['core_costed_fee']
                    if "core_costed_fee" in withdraw_tx
                    else 0
                )
                relay_fee_value = withdraw_tx['relay_fee'] - core_costed_fee

                available_gas_amount = get_fee_amount(relay_fee_value, 'sui')

                source_chain_id = withdraw_tx['src_chain_id']
                source_nonce = withdraw_tx['nonce']
                token_name = withdraw_tx['withdraw_pool']
                vaa = withdraw_tx['withdraw_vaa']

                # check relayer balance
                if sui_total_balance() < int(1e9):
                    local_logger.warning(
                        f"Relayer balance is not enough, need {relay_fee_value} sui")
                    time.sleep(5)
                    continue

                gas_used, executed, status, digest = dola_sui_lending.pool_withdraw(
                    vaa, token_name)

                if executed:
                    timestamp = int(time.time())
                    tx_gas_amount = gas_used

                    gas_price = int(
                        sui_project.client.suix_getReferenceGasPrice())
                    gas_limit = int(tx_gas_amount / gas_price)
                    gas_record.update_record({'src_chain_id': source_chain_id, 'nonce': source_nonce},
                                             {"$set": {'withdraw_gas': gas_limit, 'dst_chain_id': 0}})

                    withdraw_cost_fee = get_fee_value(tx_gas_amount, 'sui')

                    date = str(datetime.datetime.utcfromtimestamp(timestamp))
                    relay_record.update_record({'withdraw_vaa': vaa},
                                               {"$set": {'status': 'success', 'withdraw_cost_fee': withdraw_cost_fee,
                                                         'end_time': date, 'withdraw_tx_id': digest}})

                    local_logger.info("Execute sui withdraw success! ")
                    local_logger.info(
                        f"token: {token_name} source_chain: {source_chain_id} nonce: {source_nonce}")
                    local_logger.info(
                        f"relay fee: {relay_fee_value} USD, consumed fee: {get_fee_value(tx_gas_amount)} USD")
                    if available_gas_amount < tx_gas_amount:
                        call_name = withdraw_tx['call_name']
                        local_logger.warning(
                            "Execute withdraw fail on sui, not enough relay fee! ")
                        local_logger.warning(
                            f"Need gas fee: {get_fee_value(tx_gas_amount)} USD, but available gas fee: {relay_fee_value} USD"
                        )
                        local_logger.warning(
                            f"call: {call_name} source_chain: {source_chain_id}, nonce: {source_nonce}")
                else:
                    relay_record.update_record({'vaa': withdraw_tx['vaa']},
                                               {"$set": {'status': 'fail',
                                                         'reason': status}})
                    local_logger.warning("Execute sui core fail! ")
                    local_logger.warning(f"status: {status}")
            except Exception as e:
                traceback.print_exc()
                local_logger.error(f"Execute sui pool withdraw fail\n {e}")
        time.sleep(3)


def eth_pool_executor():
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    local_logger = logger.getChild("[eth_pool_executor]")
    local_logger.info("Start to relay eth withdraw vaa ^-^")

    relay_record = RelayRecord()
    gas_record = GasRecord()

    while True:
        try:
            relay_transactions = relay_record.find(
                {"status": "withdraw", "withdraw_chain_id": {"$ne": 0}})
        except Exception as e:
            local_logger.warning(f"relay record find failed! {e}")
            continue

        for withdraw_tx in relay_transactions:
            try:
                dola_chain_id = withdraw_tx['withdraw_chain_id']
                network = get_dola_network(dola_chain_id)
                dola_ethereum_sdk.set_ethereum_network(network)

                ethereum_wormhole_bridge = dola_ethereum_load.wormhole_adapter_pool_package(
                    network)
                ethereum_account = dola_ethereum_sdk.get_account()
                local_logger.info(
                    f"Ethereum account: {ethereum_account.address}")
                source_chain_id = withdraw_tx['src_chain_id']
                source_chain = get_dola_network(source_chain_id)
                source_nonce = withdraw_tx['nonce']

                vaa = withdraw_tx['withdraw_vaa']

                core_costed_fee = (
                    withdraw_tx['core_costed_fee']
                    if "core_costed_fee" in withdraw_tx
                    else 0
                )
                relay_fee_value = withdraw_tx['relay_fee'] - core_costed_fee
                available_gas_amount = get_fee_amount(relay_fee_value, get_gas_token(network))
                # check relayer balance
                if network in ['arbitrum-main', 'optimism-main'] and int(ethereum_account.balance()) < int(0.01 * 1e18):
                    local_logger.warning(
                        f"Relayer balance is not enough, need 0.01 {get_gas_token(network)}, but available {ethereum_account.balance()}")
                    time.sleep(5)
                    continue

                gas_price = int(brownie.web3.eth.gas_price)
                gas_used = ethereum_wormhole_bridge.receiveWithdraw.estimate_gas(
                    vaa, {"from": ethereum_account})

                gas_record.update_record({'src_chain_id': source_chain_id, 'nonce': source_nonce},
                                         {"$set": {'withdraw_gas': gas_used, 'dst_chain_id': dola_chain_id}})

                tx_gas_amount = int(gas_used) * gas_price

                result = ethereum_wormhole_bridge.receiveWithdraw(
                    vaa, {"from": ethereum_account})

                tx_id = result.txid
                timestamp = time.time()
                date = str(datetime.datetime.utcfromtimestamp(int(timestamp)))

                withdraw_cost_fee = get_fee_value(tx_gas_amount, get_gas_token(network))
                relay_record.update_record({'withdraw_vaa': withdraw_tx['withdraw_vaa']},
                                           {"$set": {'status': 'success', 'withdraw_cost_fee': withdraw_cost_fee,
                                                     'end_time': date, 'withdraw_tx_id': tx_id}})

                local_logger.info(f"Execute {network} withdraw success! ")
                local_logger.info(
                    f"source: {source_chain} nonce: {source_nonce}")
                local_logger.info(
                    f"relay fee: {relay_fee_value} USD, consumed fee: {get_fee_value(tx_gas_amount, get_gas_token(network))} USD")

                if available_gas_amount < tx_gas_amount:
                    local_logger.warning(
                        f"Execute withdraw success on {get_dola_network(dola_chain_id)}, but not enough relay fee! ")
                    local_logger.warning(
                        f"Need gas fee: {get_fee_value(tx_gas_amount, get_gas_token(network))} USD, but available gas fee: {relay_fee_value} USD")
                    call_name = withdraw_tx['call_name']
                    local_logger.warning(
                        f"call: {call_name} source: {source_chain}, nonce: {source_nonce}")
            except ValueError as e:
                local_logger.warning(f"Execute eth pool withdraw fail\n {e}")
                relay_record.update_record({'withdraw_vaa': withdraw_tx['withdraw_vaa']},
                                           {"$set": {'status': 'fail', 'reason': str(e)}})
            except Exception as e:
                traceback.print_exc()
                local_logger.error(f"Execute eth pool withdraw fail\n {e}")


def check_valid_call_name(call_name):
    if call_name not in ['binding', 'unbinding', 'supply', 'withdraw', 'borrow', 'repay', 'liquidate',
                         'cancel_as_collateral', 'as_collateral']:
        raise ValueError("Invalid call name!")


def get_unrelay_txs(src_chain_id, call_name, limit):
    db = mongodb()
    relay_record = db['RelayRecord']

    check_valid_call_name(call_name)

    if int(limit) > 0:
        result = list(relay_record.find(
            {'src_chain_id': int(src_chain_id), 'call_name': call_name, 'status': 'fail', 'reason': 'success'},
            {'_id': False}).limit(
            int(limit)))
    else:
        result = list(relay_record.find(
            {'src_chain_id': int(src_chain_id), 'call_name': call_name, 'status': 'fail', 'reason': 'success'},
            {'_id': False}))

    return {'result': result}


def get_unrelay_tx_by_sequence(src_chain_id, sequence):
    db = mongodb()
    relay_record = db['RelayRecord']

    return {'result': list(
        relay_record.find(
            {
                'src_chain_id': int(src_chain_id),
                'status': 'fail',
                'reason': 'success',
                'sequence': int(sequence),
            },
            {'_id': False}
        )
    )}


# The largest relay fee in total history
def get_max_relay_fee(src_chain_id, dst_chain_id, call_name):
    db = mongodb()
    gas_record = db['GasRecord']

    check_valid_call_name(call_name)

    result = list(gas_record.find(
        {"src_chain_id": int(src_chain_id), "dst_chain_id": int(dst_chain_id), "call_name": call_name}).sort(
        'core_gas', -1).limit(1))

    return calculate_relay_fee(result, int(src_chain_id), int(dst_chain_id))


# The largest relay fee of the last five transactions
def get_relay_fee(src_chain_id, dst_chain_id, call_name, feed_num):
    db = mongodb()
    gas_record = db['GasRecord']

    check_valid_call_name(call_name)

    if call_name in ['borrow', 'withdraw', 'cancel_as_collateral']:
        result = list(gas_record.find(
            {"src_chain_id": int(src_chain_id), "dst_chain_id": int(dst_chain_id), "call_name": call_name,
             "feed_nums": int(feed_num)}).sort('nonce', -1).limit(20)) or list(gas_record.find(
            {"src_chain_id": int(src_chain_id), "dst_chain_id": 0, "call_name": call_name,
             "feed_nums": int(feed_num)}).sort('nonce', -1).limit(20))
    else:
        result = list(gas_record.find(
            {"src_chain_id": int(src_chain_id), "dst_chain_id": int(dst_chain_id), "call_name": call_name}).sort(
            'nonce', -1).limit(20))
    return calculate_relay_fee(result, int(src_chain_id), int(dst_chain_id))


def calculate_relay_fee(records, src_chain_id, dst_chain_id):
    if not records:
        return {'relay_fee': '0'}

    core_gas_price = int(sui_project.client.suix_getReferenceGasPrice())

    dst_net = get_dola_network(dst_chain_id)
    if int(dst_chain_id) == 0:
        withdraw_gas_price = core_gas_price
    else:
        dola_ethereum_sdk.set_ethereum_network(dst_net)
        withdraw_gas_price = int(brownie.web3.eth.gas_price)

    max_record = max(records, key=lambda x: x['core_gas'] + x['withdraw_gas'])

    relay_fee = (calculate_core_fee(max_record['core_gas'], core_gas_price) +
                 calculate_withdraw_fee(max_record['withdraw_gas'], withdraw_gas_price, dst_net))
    src_net = get_dola_network(src_chain_id)
    relay_fee = int(get_fee_amount(relay_fee, get_gas_token(src_net)) * 1.4)
    return {'relay_fee': str(relay_fee)}


def calculate_core_fee(core_gas, gas_price):
    core_fee_amount = core_gas * gas_price
    return get_fee_value(core_fee_amount, 'sui')


def calculate_withdraw_fee(withdraw_gas, gas_price, dst_net):
    withdraw_fee_amount = withdraw_gas * gas_price
    return get_fee_value(withdraw_fee_amount, get_gas_token(dst_net))


@retry
def get_signed_vaa_by_wormhole(
        emitter: str,
        sequence: int,
        src_net: str = None
):
    wormhole_url = sui_project.network_config['wormhole_url']
    emitter_address = dola_sui_init.format_emitter_address(emitter)
    emitter_chain_id = config.NET_TO_WORMHOLE_CHAIN_ID[src_net]

    url = f"{wormhole_url}/v1/signed_vaa/{emitter_chain_id}/{emitter_address}/{sequence}"
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


def get_mongodb_uri():
    env_file = sui_project.config['dotenv']
    env_values = dotenv_values(sui_project.project_path.joinpath(env_file))
    return env_values['MONGODB_URI']


def mongodb():
    mongo_uri = get_mongodb_uri()
    client = MongoClient(mongo_uri)

    return client['DolaProtocol']


def sui_total_balance():
    return int(sui_project.client.suix_getBalance(sui_project.account.account_address, '0x2::sui::SUI')['totalBalance'])


def graph_query(block_number, limit=5):
    return gql(
        f"{{ \
              relayEvents(where: {{blockNumber_gt: {block_number}}}, orderDirection: asc, orderBy: nonce, first: {limit}) {{ \
                transactionHash \
                blockNumber \
                blockTimestamp \
                nonce \
                sequence \
                feeAmount \
                appId \
                callType \
              }} \
            }}"
    )


def check_payload_hash(left: str, right: str):
    return compare_digest(left[len(left) - len(right):], right)


def test_validate_vaa():
    network = "polygon-main"
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(network)
    tx = brownie.chain.get_transaction("0x0aa7acd7e2f38ac5b89245b88d248ced101291a147876405130b2497ca6a97b9")
    payload_on_chain = str(tx.events['LogMessagePublished']['payload'])

    vaa = '0x01000000030d00e4250bd74bc4145c6a396ae0667819bbaa2ca889b83680c68c258f96e48d89147430ec530a929c1e3184f3f96481c953277db7b33256d6581353251bb4aa8a3e0001e7993e81630a7ac1801972ec4f58f732055b3453d80e10061ca5adf681628e902d691cbd9631adedb4254f892a87fb55422106f666a4b8925244c50060a26d920002bc7361cf8d697b69b7226f6238958ca9b5ad96db28cb38fab9ceb4f6df76b9c0309e97a7d540c6a1d0f790e60347092151b0b779bbad25d7b0d1face9f84647f00038c66ab82608a92c859bdf82dda154a469583f4b4f3ada5db666ad8401745306a5953f7c88cadbb133caac0ce1fadef67f82d270e3cc5b50c77a60d22a2d5ddc301057662ac6f5df310447a35ef6a4333927a86d2eebb816dfbb5ce282212c156efb867e8f8ec02747026bba1d6352cfcf12bf06d009493c89d956834ead4fa6f147c0006acabd409b05fa6e8b29115e01ab656f96c39666d974718a548afd1af95f43a1c1942adc456af7f87dcec8aa9e6cf9417ea44152b113e07028a0f88c6385dc806010a7a85703f541e8c56d472cae26eb032fbfdbb03a147f269340c5feb5c525f4960506006dccf5ccf7274e65a50008ae73b7c05817344d00c7f624fd3dce0017494010cd318c54e79396eb74b3f3aa0369458de5441988fa1f20814a2d90e50a4dfdcb300194e3d442f443d5335f67991d4b6bdba5e77a9fe8be5369e950a3ff7b9b7cd000d02cf15b8a8f37388d4b9dc5e8064168e0d4e7fd7f3cb772737f8849fa6dc42c23a317747266267157161a1858a1d44f5c2322db96b1f9edf62e2b6dff7e3eef5000ece5943716128c953f6e669424eeb246a80ea7567d56c3b68f1584e99eaec37f73c6045c4f01b0c840e3038c2896248e357570f519a50d9e5b13dc4ba4cae81940010729dff4d8a5ff5b6944cf4390ec7e59357c531e3977541c3cead905cc60bd4d570db6f42cbd97c68ca96c9ee8a0310710b97b52d9c62864dce67bc553c0016520011febd4b93f1512ca809160d72e5c681b22c4def184c20c927249bb74913862eb90e94b6e31fbcc8fa5127e6f9c8fa4f264c3fbfd3a70f99495d395f863e99c3760012ac6fba04b170b8dbc8e7a33cef85ede1e25771efffc03024c241fc5986f1dad464d5c1a3ffbe3271a8164644bcca301b78a7277011dcc99fdd9d59be7e0af6b90064b6cbd90000000000050000000000000000000000004445c48e9b70f78506e886880a9e09b501ed1e1300000000000003e9c80001001600050617f40c0bcc0b8bdce45e73b2c19803525d3fbb020043000500000000000004780000000003938700001600052791bca1f2de4661ed88a30c99a7a9449aa84174001600050617f40c0bcc0b8bdce45e73b2c19803525d3fbb02'
    wormhole = dola_ethereum_load.womrhole_package(network)
    vm = wormhole.parseVM(vaa)
    payload = str(list(vm)[7])

    assert check_payload_hash(payload, payload_on_chain)

    dola_sui_sdk.set_dola_project_path(Path("../.."))
    payload_on_chain = dola_sui_lending.get_sui_wormhole_payload("Lnw58YkKRqvAxWrT8bMCStvsNpeLepxuktzH3ZdSx8Q")

    vaa = '0x01000000030d00c6f6a4f2bfc15541201679acd1f7fc52a99d80e7ebff8f82863276b514db870944f92b26df0b14ed7f0531de978d929e255309bd4cac494737f8bb8f0bb00a0600036218be30ec3044f56212ed877d5c5e32059a718e941f5b0d018e1230c194e0ff663f28f5d623c6da21933c0ce68f5fa121b5ffe258d08a4f77f546ed33d2885b0104ee9a20cb4e1158ddf40175d14de7a3b96c161d1b588a2bd297e00b1d014324b9669470a8af8227cb6db0455e7b86499c8cdc6a828ddd7075925a14c93e871adf010788a1d3a0ceee26b8252dbff44e0899c346ba08f8c6dcbf5c73108590d41c438475e630e87f7a20be9c739d10603983bd3d340e6d8469813601983acd0d9395600008fb6b1f8e4e4332c893dea497a62e6a95256d3d24c8e029b63ba41af7fe5c863f551bb7307f8018e6f3d2d8740f59be0ebb483df650fa06ee09c7b82b366297fb0009171eef9812d9be77d219a0d7f995ef443d6e0924f74d1a30b473e1e2f4eda22f7c3e10ad1878f1e0af23e28026b033b8133e2c50839842aaef2b38b6c771fd48010ad9e300480edfd5c5602121fe65ce28efee9c430fee0add82aa8ce21bb3fbbc2f08bd85f1981afc1554667daf8fbecf37bb44f853064a973df063c808a62d939b000d1db41b2c41c0d7f3cb56462fe61cf5ccf9b039aaf55ebb816a04867f442bb78c1ebae8ba208b7b5e05d6102f173e37e955d6305876cb5fc84a886bab6a72728b000e01edfe2fb56848ed03d89c611fe57629c605dd01afc1cebc62a948b9284a3b7909f8bc5cd9a5c4224a58b09bc37d0893fcee54d3d22e51381cd362c43e207ff6010fedd1b7fa572b445d518846748ef7d285513cf20452ba995afa8528261e3468823522d9ae67b35995ba4f6143c7ff43df725915312a8b6f6d268260d8a09b4cad011010986db3b9c91fd2fa29f4c05c9b23cad75f6b521ce8511fcd63a4c3d17108c7281fa07eb09605d7f807795fba36ac26d5a8efdde9060af9d0eddc7be69fa68a00110c7a88c15052e70293426bcddf08568213b3910df840450903b49237de2595e7656becac9991f0323c317889207884de69c2e7b4f582a5421f9f2ee9718d38450112d45b86553c2f237895c67210a1dac507a12c6d0305d23a2752eeb36e8a567dba0c7fbb571a60ec9ed5220242682dec1ef6b5ccbf6c52ced869f8713a2d0b9c4f0064b6cbf3000000000015abbce6c0c2c7cd213f4c69f8a685f6dfc1848b6e3f31dd15872f4e777d5b3e86000000000000009f0000050000000000000478001600052791bca1f2de4661ed88a30c99a7a9449aa84174001600050617f40c0bcc0b8bdce45e73b2c19803525d3fbb000000000393870001'
    wormhole = dola_ethereum_load.womrhole_package(network)
    vm = wormhole.parseVM(vaa)
    payload_by_evm = str(list(vm)[7])
    payload = dola_sui_lending.parse_vaa(vaa)

    assert check_payload_hash(payload, payload_on_chain)
    assert check_payload_hash(payload, payload_by_evm)


def main():
    init_logger()
    init_markets()
    # fix request ssl error
    fix_requests_ssl()

    # init dola monitor
    all_pools = dola_monitor.get_all_pools()

    manager = Manager()

    health = manager.Value('b', True)

    lock = manager.Lock()

    q = manager.Queue()

    pt = ProcessExecutor(executor=21)

    sui_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['sui-mainnet']
    polygon_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['polygon-main']
    optimism_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['optimism-main']
    arbitrum_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['arbitrum-main']
    base_dola_chain_id = config.NET_TO_DOLA_CHAIN_ID['base-main']

    pt.run([
        # One monitoring pool balance per chain
        functools.partial(dola_monitor.sui_pool_monitor, logger.getChild("[sui_pool_monitor]"),
                          all_pools[sui_dola_chain_id], q),
        functools.partial(dola_monitor.eth_pool_monitor, logger.getChild("[polygon_pool_monitor]"),
                          polygon_dola_chain_id,
                          all_pools[polygon_dola_chain_id], q),
        functools.partial(dola_monitor.eth_pool_monitor, logger.getChild("[optimism_pool_monitor]"),
                          optimism_dola_chain_id,
                          all_pools[optimism_dola_chain_id], q),
        functools.partial(dola_monitor.eth_pool_monitor, logger.getChild("[arbitrum_pool_monitor]"),
                          arbitrum_dola_chain_id,
                          all_pools[arbitrum_dola_chain_id], q),
        functools.partial(dola_monitor.eth_pool_monitor, logger.getChild("[base_pool_monitor]"),
                          base_dola_chain_id,
                          all_pools[base_dola_chain_id], q),
        # Protocol health monitoring
        functools.partial(dola_monitor.dola_monitor, logger.getChild("[dola_monitor]"), q, health, lock),
        # Two core executor
        functools.partial(sui_core_executor, "LendingCore1", 3, 0),
        functools.partial(sui_core_executor, "LendingCore2", 3, 1),
        functools.partial(sui_core_executor, "LendingCore3", 3, 2),
        # User transaction watcher
        functools.partial(sui_portal_watcher, health),
        functools.partial(eth_portal_watcher, health, "polygon-main"),
        functools.partial(wormhole_vaa_guardian, "polygon-main"),
        functools.partial(eth_portal_watcher, health, "arbitrum-main"),
        functools.partial(wormhole_vaa_guardian, "arbitrum-main"),
        functools.partial(eth_portal_watcher, health, "optimism-main"),
        functools.partial(wormhole_vaa_guardian, "optimism-main"),
        functools.partial(eth_portal_watcher, health, "base-main"),
        functools.partial(wormhole_vaa_guardian, "base-main"),
        # User withdraw watcher
        functools.partial(pool_withdraw_watcher, health),
        # User withdraw executor
        functools.partial(sui_pool_executor, "LendingPool"),
        eth_pool_executor,
    ])


if __name__ == "__main__":
    main()
