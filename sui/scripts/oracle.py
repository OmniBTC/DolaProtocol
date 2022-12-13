import time

import ccxt

import init
import load


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


def feed(symbol, catalog):
    kucoin = ccxt.kucoin()
    kucoin.load_markets()
    while True:
        try:
            price = kucoin.fetch_ticker(symbol)['close']
        except:
            continue
        oracle = load.oracle_package()
        oracle.oracle.update_token_price(
            oracle.oracle.OracleCap[-1],
            oracle.oracle.PriceOracle[-1],
            list(bytes(catalog.replace("0x", ""), 'ascii')),
            int(price * 100)
        )
        timestamp = time.time()
        oracle.oracle.update_timestamp(
            oracle.oracle.OracleCap[-1],
            oracle.oracle.PriceOracle[-1],
            int(timestamp)
        )
        time.sleep(1)


if __name__ == '__main__':
    feed("BTC/USDT", init.btc())
