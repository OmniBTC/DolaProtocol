import base64
import logging
import time
from pprint import pprint

import ccxt
import requests
import sui_brownie
from sui_brownie import Argument, U16

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


def feed_token_price_by_pyth(symbol):
    dola_protocol = load.dola_protocol_package()

    pyth_fee_amount = 0
    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    sui_project.batch_transaction(
        actual_params=[
            governance_genesis,
            wormhole_state,
            pyth_state(),
            get_price_info_object(symbol),
            price_oracle,
            get_pool_id(symbol),
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
            ]
        ]
    )


def build_feed_transaction_block(dola_protocol, basic_param_num, sequence):
    return [
        dola_protocol.oracle.feed_token_price_by_pyth,
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


def feed_market_price(symbols=("BTC/USDT", "ETH/USDT")):
    kucoin = ccxt.kucoin()
    kucoin.load_markets()

    sui_project.active_account("Oracle")
    oracle = load.oracle_package()
    while True:
        check_sui_objects()
        for symbol in symbols:
            try:
                price = kucoin.fetch_ticker(symbol)['close']
                oracle.oracle.update_token_price(
                    oracle.oracle.OracleCap[-1],
                    oracle.oracle.PriceOracle[-1],
                    get_pool_id(symbol),
                    int(price * 100)
                )
            except Exception as e:
                print(e)
                continue
        time.sleep(600)


def test_verify_oracle():
    dola_protocol = load.dola_protocol_package()
    kucoin = ccxt.kucoin()
    kucoin.load_markets()

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
    kucoin_price = kucoin.fetch_ticker(f"{symbol}T")['close']
    print(f"Kucoin price:{kucoin_price}")
    if pyth_price > kucoin_price:
        bias = 1 - kucoin_price / pyth_price
    else:
        bias = 1 - pyth_price / kucoin_price
    print(f"Bias:{bias}")
    assert bias < 0.01


def check_guard_price(symbol):
    dola_protocol = load.dola_protocol_package()

    price_oracle = sui_project.network_config['objects']['PriceOracle']
    pool_id = get_pool_id(symbol)
    result = dola_protocol.oracle.check_guard_price.inspect(
        price_oracle,
        [pool_id],
        init.clock()
    )
    if result['effects']['status']['status'] == 'failure':
        raise ValueError(symbol)


def oracle_guard(symbols=None):
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

    if symbols is None:
        symbols = []
    sui_project.active_account("Oracle")
    while True:
        try:
            for symbol in symbols:
                local_logger.info(f"Check {symbol} price guard time")
                check_guard_price(symbol)
        except ValueError as s:
            local_logger.info(f"Update {s} price")
            feed_token_price_by_pyth(str(s))
        except Exception as e:
            local_logger.warning(e)
        finally:
            time.sleep(1)


if __name__ == '__main__':
    # deploy_oracle()
    # print(get_price_info_object('ETH/USD'))
    oracle_guard(["USDT/USD"])
    # batch_feed_token_price_by_pyth(["BTC/USD", "USDT/USD", "USDC/USD", "SUI/USD", "ETH/USD", "MATIC/USD"])
