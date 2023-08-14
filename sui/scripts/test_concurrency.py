import functools

import requests
from retrying import retry

from dola_sui_sdk import sui_project, init
from dola_sui_sdk.lending import portal_supply, portal_borrow
from parallelism import ProcessExecutor


@retry
def get_supply_relay_fee():
    url = f'https://lending-relay-fee.omnibtc.finance/relay_fee/0/0/supply'
    if sui_project.network == 'sui-testnet':
        url = f"http://[::]:5000/relay_fee/0/0/supply"

    response = requests.get(url)
    return response.json()['relay_fee']


@retry
def get_borrow_relay_fee(feed_nums):
    url = f'https://lending-relay-fee.omnibtc.finance/relay_fee/0/0/borrow/{feed_nums}'
    if sui_project.network == 'sui-testnet':
        url = f"http://[::]:5000/relay_fee/0/0/borrow/{feed_nums}"

    response = requests.get(url)
    return response.json()['relay_fee']


def supply(account):
    sui_project.active_account(account)
    amount = int(0.001 * 1e9)
    relay_fee = get_supply_relay_fee()
    for _ in range(100):
        portal_supply(init.sui()["coin_type"], amount, bridge_fee=relay_fee)


def supplys():
    pt = ProcessExecutor(executor=4)
    pt.run(
        [
            functools.partial(supply, "TestAccount"),
            functools.partial(supply, "LendingLiquidate"),
        ]
    )


def borrow(account):
    feed_nums = 4
    sui_project.active_account(account)
    amount = int(0.001 * 1e9)
    relay_fee = get_borrow_relay_fee(feed_nums)
    print("borrow", account, relay_fee)

    for _ in range(10):
        portal_borrow(pool_addr=init.sui()["coin_type"], amount=amount, dst_chain_id=0, bridge_fee=relay_fee)


def borrows():
    pt = ProcessExecutor(executor=4)
    pt.run(
        [functools.partial(borrow, "TestAccount"),
         functools.partial(borrow, "LendingLiquidate"),
         ]
    )


if __name__ == "__main__":
    borrows()
