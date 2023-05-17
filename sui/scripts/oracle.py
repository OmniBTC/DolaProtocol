import base64
import time
from pathlib import Path

import ccxt
import requests
import sui_brownie
from dola_sui_sdk import load, sui_project, init


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


def load_pyth():
    return sui_brownie.SuiPackage(
        package_id=sui_project.network_config['packages']['pyth'],
        package_path=Path.home().joinpath(Path(
            ".move/https___github_com_pyth-network_pyth-crosschain_git_61c9ab5c65face02841739ee0ea7c8ee488322b5"
            "/target_chains/sui/contracts")),
    )


def get_feed_vaa(symbol):
    pyth_service_url = sui_project.network_config['pyth_service_url']
    feed_id = sui_project.network_config['oracle']['feed_id'][symbol].replace("0x", "")
    url = f"{pyth_service_url}/api/latest_vaas?ids[]={feed_id}"
    response = requests.get(url)
    vaa = list(response.json())[0]
    return f"0x{base64.b64decode(vaa).hex()}"


def get_price_info_object(symbol):
    pyth = load_pyth()
    feed_vaa = sui_project.network_config['oracle']['feed_id'][symbol].replace("0x", "")
    feed_id = bytes.fromhex(feed_vaa.replace("0x", ""))
    result = pyth.state.get_price_info_object_id.inspect(pyth_state(), list(feed_id))
    return f"0x{bytes(result['results'][0]['returnValues'][0][0]).hex()}"


def get_pyth_fee():
    pyth = load_pyth()

    result = pyth.state.get_base_update_fee.inspect(pyth_state())
    return parse_u64(result['results'][0]['returnValues'][0][0])


def feed_token_price_by_pyth(symbol):
    dola_protocol = load.dola_protocol_package()

    pyth_fee_amount = get_pyth_fee()
    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    result = sui_project.pay_sui([pyth_fee_amount])
    fee_coin = result['objectChanges'][-1]['objectId']

    dola_protocol.oracle.feed_token_price_by_pyth(
        governance_genesis,
        wormhole_state,
        pyth_state(),
        get_price_info_object(symbol),
        dola_protocol.oracle.PriceOracle[-1],
        get_pool_id(symbol),
        list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
        init.clock(),
        fee_coin
    )


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
        dola_protocol.oracle.PriceOracle[-1],
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
    elif symbol == "ETH/USD":
        return 3
    elif symbol == "MATIC/USD":
        return 4
    elif symbol == "SUI/USD":
        return 5


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


if __name__ == '__main__':
    # deploy_oracle()
    # feed_token_price_for_pyth('BTC/USD')
    print(check_fresh_price('BTC/USD'))
