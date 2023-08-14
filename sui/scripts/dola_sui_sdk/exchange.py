import os
import time
import ccxt
from concurrent.futures import ThreadPoolExecutor, as_completed


class ExchangeManager:

    def __init__(self):
        self.exchanges = self.setup_exchanges()

    def setup_exchanges(self):
        exchanges = []
        # List of exchanges to set up. Use 'okx,kucoin,coinbase' as default if not set.
        exchange_names = os.environ.get("EXCHANGE_NAMES", "okx,kucoin").split(",")

        for exchange_name in exchange_names:
            api_key = os.environ.get(f"{exchange_name.upper()}_API_KEY", None)
            secret = os.environ.get(f"{exchange_name.upper()}_SECRET", None)

            try:
                exchange_class = getattr(ccxt, exchange_name.strip())

                if api_key and secret:
                    exchange = exchange_class({"apiKey": api_key, "secret": secret})
                else:
                    print(f"Note: Using public API for {exchange_name}. Rate limits may apply.")
                    exchange = exchange_class()  # If no keys are provided, initialize without them

                exchange.load_markets()
                exchanges.append(exchange)

            except Exception as e:
                print(f"Error initializing {exchange_name}. Error: {e}")
                continue  # Continue to the next exchange

        return exchanges

    def fetch_ticker_with_delay(self, exchange, symbol):
        return exchange.fetch_ticker(symbol)

    def fetch_fastest_ticker(self, symbol):
        with ThreadPoolExecutor(max_workers=len(self.exchanges)) as executor:
            futures = {executor.submit(
                self.fetch_ticker_with_delay, exchange, symbol): exchange for exchange in self.exchanges}

            for future in as_completed(futures):
                try:
                    ticker = future.result()
                    exchange_used = futures[future]
                    print(f"Received ticker from {exchange_used.name}")  # 打印当前API由哪个交易所返回的
                    return ticker
                except:
                    continue
        raise ValueError(
            f"Failed to fetch ticker for {symbol} from all exchanges.")