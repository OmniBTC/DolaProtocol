import time
from pathlib import Path

import requests

import dola_ethereum_sdk
import dola_sui_sdk
from dola_sui_sdk import interfaces, lending


def get_user_ids_by_hf(min_hf, max_hf):
    host = 'https://crossswap-pre.coming.chat'
    url = f'{host}/lending/v1/filterUsers?minHealthFactor={min_hf}&maxHealthFactor={max_hf}'

    response = requests.get(url)
    return response.json()['users'] if response.status_code == 200 else []


def get_pools(pool_id):
    pool_infos = interfaces.get_all_pool_liquidity(pool_id)['pool_infos']

    pools = []
    for pool_info in pool_infos:
        pool_address = pool_info['pool_address']
        dola_address = bytes(pool_address['dola_address']).hex()
        dola_chain_id = pool_address['dola_chain_id']
        pools.append((dola_chain_id, f'0x{dola_address}'))
    return pools


def check_liquidator_liquidity(liquidator_user_id, pool_id):
    lending_info = interfaces.get_user_lending_info(liquidator_user_id)

    collateral_infos = lending_info['collateral_infos']
    liquid_asset_infos = lending_info['liquid_asset_infos']
    return any(
        collateral_info['pool_id'] == pool_id
        for collateral_info in collateral_infos,
    ) or any(
        liquid_asset_info['pool_id'] == pool_id
        for liquid_asset_info in liquid_asset_infos
    )


def liquidation_bot(liquidator_user_id):
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    while True:
        # get user ids with health factor < 1
        user_ids = get_user_ids_by_hf(0, 1)

        for user_id in user_ids:
            lending_info = interfaces.get_user_lending_info(user_id)
            debt_infos = lending_info['debt_infos']
            max_debt_info = max(debt_infos, key=lambda x: x['debt_value'])
            repay_pool_id = max_debt_info['dola_pool_id']

            if check_liquidator_liquidity(liquidator_user_id, repay_pool_id):
                collateral_infos = lending_info['collateral_infos']
                max_collateral_info = max(collateral_infos, key=lambda x: x['collateral_value'])
                liquidate_pool_id = max_collateral_info['dola_pool_id']
                lending.portal_liquidate(repay_pool_id, liquidate_pool_id, user_id)

        time.sleep(1)


if __name__ == '__main__':
    liquidation_bot(2)
