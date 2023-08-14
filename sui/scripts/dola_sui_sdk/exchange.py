import os
import time
import ccxt
from concurrent.futures import ThreadPoolExecutor, as_completed


class ExchangeManager:

    def __init__(self):
        self.exchanges = self.setup_exchanges()

    def setup_exchanges(self):
        exchanges = []

        # Setup Binance
        binance_api_key = os.environ.get("BINANCE_API_KEY", None)
        binance_secret = os.environ.get("BINANCE_SECRET", None)
        if binance_api_key and binance_secret:
            binance = ccxt.binance(
                {"apiKey": binance_api_key, "secret": binance_secret})
            binance.load_markets()
            exchanges.append(binance)

        # Setup OKEx
        okex_api_key = os.environ.get("OKEX_API_KEY", None)
        okex_secret = os.environ.get("OKEX_SECRET", None)
        if okex_api_key and okex_secret:
            okex = ccxt.okex({"apiKey": okex_api_key, "secret": okex_secret})
            okex.load_markets()
            exchanges.append(okex)

        return exchanges

    def fetch_ticker_with_delay(self, exchange, symbol):
        # 使用rate_limit属性进行延迟
        time.sleep(exchange.rate_limit / 1000)  # ccxt中的rate_limit是毫秒
        return exchange.fetch_ticker(symbol)['close']

    def fetch_fastest_ticker(self, symbol):
        with ThreadPoolExecutor(max_workers=len(self.exchanges)) as executor:
            futures = {executor.submit(
                self.fetch_ticker_with_delay, exchange, symbol): exchange for exchange in self.exchanges}

            for future in as_completed(futures):
                try:
                    ticker = future.result()
                    return ticker  # 返回最先获取到的ticker
                except:
                    continue
        raise ValueError(
            f"Failed to fetch ticker for {symbol} from all exchanges.")
