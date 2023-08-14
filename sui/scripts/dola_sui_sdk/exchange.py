import os
import time
import ccxt
from concurrent.futures import ThreadPoolExecutor, as_completed


class ExchangeManager:

    def __init__(self):
        self.exchanges = self.setup_exchanges()

    def setup_exchanges(self):
        exchanges = []

        # List of exchanges to set up
        exchange_names = ['okex']  # Add more exchanges if needed in future

        for exchange_name in exchange_names:
            api_key = os.environ.get(f"{exchange_name.upper()}_API_KEY", None)
            secret = os.environ.get(f"{exchange_name.upper()}_SECRET", None)

            if api_key and secret:
                exchange_class = getattr(ccxt, exchange_name)
                exchange = exchange_class({"apiKey": api_key, "secret": secret})
                exchange.load_markets()
                exchanges.append(exchange)

        return exchanges


    def fetch_ticker_with_delay(self, exchange, symbol):
        # 使用rate_limit属性进行延迟
        time.sleep(1)  # ccxt中的rate_limit是毫秒
        return exchange.fetch_ticker(symbol)

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
