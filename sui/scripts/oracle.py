import time

import ccxt

from dola_sui_sdk import load, sui_project


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


def feed(symbols=("BTC/USDT", "ETH/USDT")):
    kucoin = ccxt.kucoin()
    kucoin.load_markets()

    sui_project.active_account("Oracle")
    oracle = load.oracle_package()
    while True:
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
        time.sleep(1)


if __name__ == '__main__':
    feed(("BTC/USDT", "ETH/USDT", "MATIC/USDT", "APT/USDT", "BNB/USDT"))
