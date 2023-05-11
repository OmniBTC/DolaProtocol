import time
from pathlib import Path
from pprint import pprint

import ccxt
import sui_brownie
from dola_sui_sdk import load, sui_project


def pyth_state():
    return sui_project.network_config['objects']['PythState']


def load_pyth():
    return sui_brownie.SuiPackage(
        package_id=sui_project.network_config['packages']['pyth'],
        package_path=Path.home().joinpath(Path(
            ".move/https___github_com_OmniBTC_pyth-crosschain_git_8601609d6f4f64fb9a42ec7704aae3cf3a47e140/target_chains/sui/contracts")),
    )


def get_pyth_price(symbol):
    pyth = load_pyth()

    feed_id = sui_project.network_config['oracle'][symbol].replace("0x", "")
    price_info_object = pyth.pyth.price_feed_exists.inspect(pyth_state(), list(bytes.fromhex(feed_id)))
    pprint(price_info_object)


def get_pool_id(symbol):
    if symbol == "BTC/USDT":
        return 0
    elif symbol == "ETH/USDT":
        return 3
    elif symbol == "MATIC/USDT":
        return 4
    elif symbol == "APT/USDT":
        return 5
    elif symbol == "BNB/USDT":
        return 6


def get_prices(symbols=("BTC/USDT", "ETH/USDT")):
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


def feed(symbols=("BTC/USDT", "ETH/USDT")):
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
    get_pyth_price("BTC/USD")
