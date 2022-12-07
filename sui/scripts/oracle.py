import time

from scripts import load


def feed():
    while True:
        timestamp = time.time()
        oracle = load.oracle_package()
        oracle.oracle.update_timestamp(
            oracle.oracle.OracleCap[-1],
            oracle.oracle.PriceOracle[-1],
            int(timestamp)
        )
        time.sleep(1)


if __name__ == '__main__':
    feed()
