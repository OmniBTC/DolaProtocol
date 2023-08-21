import base64
import logging
import time
from pprint import pprint

import ccxt
import requests
import sui_brownie
from sui_brownie import Argument, U16

import config
from dola_sui_sdk import load, sui_project, init


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


def parse_u64(data: list):
    output = 0
    for i in range(8):
        output = (output << 8) + int(data[7 - i])
    return output


def parse_u256(data: list):
    output = 0
    for i in range(32):
        output = (output << 8) + int(data[31 - i])
    return output


def pyth_state():
    return sui_project.network_config['objects']['PythState']


def get_feed_vaa(symbol):
    pyth_service_url = sui_project.network_config['pyth_service_url']
    feed_id = sui_project.network_config['oracle']['feed_id'][symbol].replace("0x", "")
    url = f"{pyth_service_url}/api/latest_vaas?ids[]={feed_id}"
    response = requests.get(url)
    vaa = list(response.json())[0]
    return f"0x{base64.b64decode(vaa).hex()}"


def get_batch_feed_vaa(symbols=None):
    if symbols is None:
        symbols = []
    pyth_service_url = sui_project.network_config['pyth_service_url']
    feed_ids = []

    url = f"{pyth_service_url}/api/latest_vaas?"

    feed_ids.extend(
        sui_project.network_config['oracle']['feed_id'][symbol]
        for symbol in symbols
    )

    for feed_id in feed_ids:
        url = f"{url}ids[]={feed_id}&"
    response = requests.get(url)
    vaas = response.json()
    return [f"0x{base64.b64decode(vaa).hex()}" for vaa in vaas]


def get_price_info_object(symbol):
    pyth = load.pyth_package()
    feed_vaa = sui_project.network_config['oracle']['feed_id'][symbol].replace("0x", "")
    feed_id = bytes.fromhex(feed_vaa.replace("0x", ""))
    result = pyth.state.get_price_info_object_id.inspect(pyth_state(), list(feed_id))
    return f"0x{bytes(result['results'][0]['returnValues'][0][0]).hex()}"


def load_sui_package():
    return sui_brownie.SuiPackage(
        package_id="0x2",
        package_name="Sui"
    )


def get_pyth_fee():
    pyth = load.pyth_package()

    result = pyth.state.get_base_update_fee.inspect(pyth_state())
    return parse_u64(result['results'][0]['returnValues'][0][0])


def get_updatable_asset_ids(asset_ids):
    objects = [config.DOLA_POOL_ID_TO_PRICE_INFO_OBJECT[asset_id] for asset_id in asset_ids]
    results = sui_project.client.sui_multiGetObjects(objects, {'showContent': True})
    current_timestamp = int(time.time())
    updatable_feed_ids = []

    for (asset_id, result) in zip(asset_ids, results):
        price_info = result['data']['content']['fields']['price_info']
        price = price_info['fields']['price_feed']['fields']['price']
        timestamp = int(price['fields']['timestamp'])
        if current_timestamp - timestamp < 60:
            updatable_feed_ids.append(asset_id)

    return updatable_feed_ids


def update_token_price_by_pyth(pool_id):
    dola_protocol = load.dola_protocol_package()

    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    price_info_object = config.DOLA_POOL_ID_TO_PRICE_INFO_OBJECT[pool_id]

    dola_protocol.oracle.update_token_price_by_pyth(
        governance_genesis,
        price_info_object,
        price_oracle,
        pool_id,
        init.clock()
    )


def feed_token_price_by_pyth(pool_id, simulate=True, kraken=None):
    dola_protocol = load.dola_protocol_package()

    pyth_fee_amount = 1
    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    pyth_state = sui_project.network_config['objects']['PythState']
    symbol = config.DOLA_POOL_ID_TO_SYMBOL[pool_id]

    if simulate:
        vaa = get_feed_vaa(symbol)
        price_info_object = get_price_info_object(symbol)
        result = sui_project.batch_transaction_inspect(
            actual_params=[
                governance_genesis,
                wormhole_state,
                pyth_state,
                price_info_object,
                price_oracle,
                pool_id,
                list(bytes.fromhex(vaa.replace("0x", ""))),
                init.clock(),
                pyth_fee_amount
            ],
            transactions=[
                [
                    dola_protocol.oracle.feed_token_price_by_pyth_v2,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
                    ],
                    []
                ],
                [
                    dola_protocol.oracle.get_token_price,
                    [
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                    ],
                    []
                ]
            ]
        )

        decimal = int(result['results'][2]['returnValues'][1][0][0])

        pyth_price = parse_u256(result['results'][2]['returnValues'][0][0]) / (10 ** decimal)

        kraken_price = kraken.fetch_ticker(symbol)['close']

        if pyth_price > kraken_price:
            deviation = 1 - kraken_price / pyth_price
        else:
            deviation = 1 - pyth_price / kraken_price

        deviation_threshold = config.SYMBOL_TO_DEVIATION[symbol]
        if deviation > deviation_threshold:
            raise ValueError(f"The oracle price difference is too large! {symbol} price deviation: {deviation}")
    else:
        sui_project.batch_transaction(
            actual_params=[
                governance_genesis,
                wormhole_state,
                pyth_state,
                get_price_info_object(symbol),
                price_oracle,
                pool_id,
                list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
                init.clock(),
                pyth_fee_amount
            ],
            transactions=[
                [
                    dola_protocol.oracle.feed_token_price_by_pyth_v2,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
                    ],
                    []
                ]
            ]
        )


def build_feed_transaction_block(dola_protocol, basic_param_num, sequence):
    return [
        dola_protocol.oracle.feed_token_price_by_pyth_v2,
        [
            Argument("Input", U16(basic_param_num - 5)),
            Argument("Input", U16(basic_param_num - 4)),
            Argument("Input", U16(basic_param_num - 3)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 0)),
            Argument("Input", U16(basic_param_num - 2)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 1)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 2)),
            Argument("Input", U16(basic_param_num - 1)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 3)),
        ],
        []
    ]


def batch_feed_token_price_by_pyth(symbols):
    dola_protocol = load.dola_protocol_package()

    pyth_fee_amount = get_pyth_fee() / 5 + 1
    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    basic_params = [
        governance_genesis,
        wormhole_state,
        pyth_state(),
        price_oracle,
        init.clock(),
    ]

    feed_params = []
    transaction_blocks = []
    for symbol in symbols:
        feed_params += [
            get_price_info_object(symbol),
            get_pool_id(symbol),
            list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
            pyth_fee_amount
        ]
        transaction_blocks.append(
            build_feed_transaction_block(dola_protocol, len(basic_params), len(transaction_blocks)))

    result = sui_project.batch_transaction(
        actual_params=basic_params + feed_params,
        transactions=transaction_blocks,
        gas_budget=2000000000
    )
    pprint(result)


def check_fresh_price(symbol):
    dola_protocol = load.dola_protocol_package()

    return dola_protocol.oracle.check_fresh_price.inspect(
        dola_protocol.oracle.PriceOracle[-1],
        get_pool_id(symbol),
        init.clock()
    )


def get_token_price(symbol):
    dola_protocol = load.dola_protocol_package()

    result = dola_protocol.oracle.get_token_price.inspect(
        sui_project.network_config['objects']['PriceOracle'],
        get_pool_id(symbol)
    )
    decimal = int(result['results'][0]['returnValues'][1][0][0])
    print(decimal)
    return parse_u256(result['results'][0]['returnValues'][0][0]) / (10 ** decimal)


def get_pool_id(symbol):
    if symbol == "BTC/USD":
        return 0
    elif symbol == "USDT/USD":
        return 1
    elif symbol == "USDC/USD":
        return 2
    elif symbol == "SUI/USD":
        return 3
    elif symbol == "ETH/USD":
        return 4
    elif symbol == "MATIC/USD":
        return 5
    elif symbol == "ARB/USD":
        return 6
    elif symbol == "OP/USD":
        return 7


def get_market_prices(symbols=("BTC/USDT", "ETH/USDT")):
    api = ccxt.kucoin()
    api.load_markets()
    prices = {}

    for symbol in symbols:
        result = api.fetch_ticker(symbol=symbol)
        price = result["close"]
        print(f"Symbol:{symbol}, price:{price}")
        prices[symbol] = price
    return prices


def check_sui_objects():
    sui_objects = sui_project.get_account_sui()
    if len(sui_objects) > 1:
        sui_project.pay_all_sui()


def test_verify_oracle():
    dola_protocol = load.dola_protocol_package()
    coinbase = ccxt.coinbase()
    coinbase.load_markets()

    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    pyth_state = sui_project.network_config['objects']['PythState']
    pyth_fee_amount = 1

    symbol = "ETH/USD"
    pool_id = get_pool_id(symbol)

    result = sui_project.batch_transaction_inspect(
        actual_params=[
            governance_genesis,
            wormhole_state,
            pyth_state,
            get_price_info_object(symbol),
            price_oracle,
            pool_id,
            list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
            init.clock(),
            pyth_fee_amount
        ],
        transactions=[
            [
                dola_protocol.oracle.feed_token_price_by_pyth,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    Argument("Input", U16(5)),
                    Argument("Input", U16(6)),
                    Argument("Input", U16(7)),
                    Argument("Input", U16(8)),
                ],
                []
            ],
            [
                dola_protocol.oracle.get_token_price,
                [
                    Argument("Input", U16(4)),
                    Argument("Input", U16(5)),
                ],
                []
            ]
        ]
    )

    decimal = int(result['results'][2]['returnValues'][1][0][0])

    pyth_price = parse_u256(result['results'][2]['returnValues'][0][0]) / (10 ** decimal)
    print("\n")
    print(f"Pyth price:{pyth_price}")

    coinbase_price = coinbase.fetch_ticker(symbol)['close']
    print(f"Coinbase price:{coinbase_price}")
    if pyth_price > coinbase_price:
        deviation = 1 - coinbase_price / pyth_price
    else:
        deviation = 1 - pyth_price / coinbase_price
    print(f"Bias:{deviation}")
    assert deviation < 0.01


def check_guard_price(symbol):
    dola_protocol = load.dola_protocol_package()

    price_oracle = sui_project.network_config['objects']['PriceOracle']
    pool_id = get_pool_id(symbol)
    result = dola_protocol.oracle.check_guard_price.inspect(
        price_oracle,
        [pool_id],
        init.clock()
    )
    return result['effects']['status']['status'] == 'failure'


def oracle_guard(pool_ids=None):
    """Check price guard time and update price termly

    :return:
    """
    FORMAT = '%(asctime)s - %(funcName)s - %(levelname)s - %(name)s: %(message)s'
    logger = logging.getLogger()
    logger.setLevel("INFO")
    # create console handler with a higher log level
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)

    ch.setFormatter(ColorFormatter(FORMAT))

    logger.addHandler(ch)
    local_logger = logger.getChild("oracle_guard")

    kraken = ccxt.kraken()
    kraken.load_markets()

    if pool_ids is None:
        pool_ids = []

    sui_project.active_account("OracleGuard")
    symbols = [config.DOLA_POOL_ID_TO_SYMBOL[pool_id] for pool_id in pool_ids]

    while True:
        try:
            for (pool_id, symbol) in zip(pool_ids, symbols):

                local_logger.info(f"Check {symbol} price guard time")
                if check_guard_price(symbol):
                    local_logger.info(f"Update {symbol} price")
                    try:
                        update_token_price_by_pyth(pool_id)
                    except Exception as e:
                        local_logger.warning(f'Update token price failed: {e}')
                        local_logger.info('Try feed token price...')
                        feed_token_price_by_pyth(pool_id, simulate=False, kraken=kraken)
        except Exception as e:
            local_logger.warning(e)
        finally:
            time.sleep(1)


if __name__ == '__main__':
    oracle_guard(list(range(9)))
