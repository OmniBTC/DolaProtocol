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
        exchange_names = os.environ.get("EXCHANGE_NAMES", "").split(",")

        for exchange_name in exchange_names:
            api_key = os.environ.get(f"{exchange_name.upper()}_API_KEY", None)
            secret = os.environ.get(f"{exchange_name.upper()}_SECRET", None)

            if api_key and secret:
                try:
                    exchange_class = getattr(ccxt, exchange_name.strip())
                    exchange = exchange_class({"apiKey": api_key, "secret": secret})
                    exchange.load_markets()
                    exchanges.append(exchange)
                except AttributeError:  # If ccxt does not have the mentioned exchange
                    print(f"Warning: {exchange_name} not found in ccxt. Skipping.")

        return exchanges

    def fetch_ticker_with_delay(self, exchange, symbol):
        time.sleep(0.1)
        return exchange.fetch_ticker(symbol)

    def fetch_fastest_ticker(self, symbol):
        with ThreadPoolExecutor(max_workers=len(self.exchanges)) as executor:
            futures = {executor.submit(
                self.fetch_ticker_with_delay, exchange, symbol): exchange for exchange in self.exchanges}

            for future in as_completed(futures):
                try:
                    ticker = future.result()
                    return ticker
                except:
                    continue
        raise ValueError(
            f"Failed to fetch ticker for {symbol} from all exchanges.")