import time

from scripts import load


def feed():
    while True:
        timestamp = time.time()
        time_oracle_package = load.time_oracle_package()
        time_oracle_package.update_timestamp(
            time_oracle_package.timestamp.OracleCap[-1],
            time_oracle_package.timestamp.Timestamp[-1],
            int(timestamp)
        )
        time.sleep(1)


if __name__ == '__main__':
    feed()
