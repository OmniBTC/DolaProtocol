import time
from pathlib import Path

import requests
from retrying import retry

import config
import dola_ethereum_sdk
import dola_sui_sdk
import sms
from dola_sui_sdk import interfaces, lending, sui_project


@retry
def get_user_ids_by_hf(min_hf, max_hf):
    host = 'https://crossswap.coming.chat'
    if sui_project.network == 'sui-testnet':
        host = 'https://crossswap-pre.coming.chat'
    url = f'{host}/lending/v1/filterUsers?minHealthFactor={min_hf}&maxHealthFactor={max_hf}'

    response = requests.get(url)
    return response.json()['users'] if response.status_code == 200 else []


@retry
def get_liquidate_relay_fee(feed_nums):
    url = f'https://lending-relay-fee.omnibtc.finance/relay_fee/0/0/liquidate/{feed_nums}'
    if sui_project.network == 'sui-testnet':
        url = f"http://[::]:5000/relay_fee/0/0/liquidate/{feed_nums}"

    response = requests.get(url)
    return response.json()['relay_fee']


def get_pools(pool_id):
    pool_infos = interfaces.get_all_pool_liquidity(pool_id)['pool_infos']

    pools = []
    for pool_info in pool_infos:
        pool_address = pool_info['pool_address']
        dola_address = bytes(pool_address['dola_address']).hex()
        dola_chain_id = pool_address['dola_chain_id']
        pools.append((dola_chain_id, f'0x{dola_address}'))
    return pools


def check_liquidator_liquidity(liquidator_lending_info, pool_id):
    collateral_infos = liquidator_lending_info['collateral_infos']
    liquid_asset_infos = liquidator_lending_info['liquid_asset_infos']
    return (any(collateral_info['dola_pool_id'] == pool_id for collateral_info in collateral_infos) or
            any(liquid_asset_info['dola_pool_id'] == pool_id for liquid_asset_info in liquid_asset_infos))


def get_user_feed_tokens(lending_info):
    collateral_infos = lending_info['collateral_infos']
    debt_infos = lending_info['debt_infos']

    collateral_ids = [collateral_info['dola_pool_id'] for collateral_info in collateral_infos]
    debt_ids = [debt_info['dola_pool_id'] for debt_info in debt_infos]

    return collateral_ids + debt_ids


def get_liquidate_feed_tokens(liquidator_lending_info, violator_lending_info):
    liquidator_feed_tokens = get_user_feed_tokens(liquidator_lending_info)

    violator_feed_tokens = get_user_feed_tokens(violator_lending_info)

    return list(set(liquidator_feed_tokens + violator_feed_tokens))


def liquidation_bot(liquidator_user_id):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    while True:
        try:

            # get user ids with health factor < 1
            user_ids = get_user_ids_by_hf(0, 1)

            for user_id in user_ids:
                user_id = user_id['userId']
                violator_lending_info = interfaces.get_user_lending_info(user_id)
                debt_infos = violator_lending_info['debt_infos']
                max_debt_info = max(debt_infos, key=lambda x: x['debt_value'])
                repay_pool_id = max_debt_info['dola_pool_id']

                liquidator_lending_info = interfaces.get_user_lending_info(liquidator_user_id)

                # check whether the liquidator can pay the debt
                if check_liquidator_liquidity(liquidator_lending_info, repay_pool_id):
                    collateral_infos = violator_lending_info['collateral_infos']
                    max_collateral_info = max(collateral_infos, key=lambda x: x['collateral_value'])
                    liquidate_pool_id = max_collateral_info['dola_pool_id']

                    liquidate_feed_tokens = get_liquidate_feed_tokens(liquidator_lending_info, violator_lending_info)
                    feed_nums = len(liquidate_feed_tokens)
                    relay_fee = get_liquidate_relay_fee(feed_nums)
                    lending.portal_liquidate(repay_pool_id, liquidate_pool_id, user_id, bridge_fee=relay_fee)
                    # todo: better ensure that the liquidation is completed properly
                    time.sleep(60)
                else:
                    symbol = config.DOLA_POOL_ID_TO_SYMBOL(repay_pool_id)
                    msg = f'liquidator {liquidator_user_id} has no liquidity to repay user {user_id} {symbol} debt'
                    sms.notify(msg)
        except Exception as e:
            sms.notify(f'liquidation failed, {e}')
        time.sleep(5)


if __name__ == '__main__':
    sui_project.active_account("Liquidator")
    liquidation_bot(1)
