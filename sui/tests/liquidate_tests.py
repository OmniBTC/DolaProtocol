import pprint

from dola_sui_sdk import lending, init, interfaces, load, sui_project


def set_mint_cap(user):
    sui_project.active_account("TestAccount")
    admin = sui_project.accounts[user].account_address
    init.add_test_coins_admin(admin)


def supply_token(account, token, amount):
    sui_project.active_account(account)
    init.force_claim_test_coin(token, amount)
    lending.portal_supply(token)


def borrow_token(account, token, amount):
    sui_project.active_account(account)
    lending.portal_borrow_local(token, amount)


def repay_token(account, token):
    sui_project.active_account(account)
    lending.portal_repay(token)
    lending.portal_withdraw_local(token)


def liquidate_user(liquidator, violator, collateral, debt, deposit_amount):
    sui_project.active_account(liquidator)
    violator = sui_project.accounts[violator].account_address
    # get violator user id
    violator_id = interfaces.get_dola_user_id(violator.replace('0x', ''))['dola_user_id']
    # init.force_claim_test_coin(debt, deposit_amount / 1e8)
    lending.portal_liquidate(debt, deposit_amount, collateral, 0, violator_id)


def manipulate_oracle(deployer, pool_id, price):
    sui_project.active_account(deployer)
    oracle = load.oracle_package()
    oracle.oracle.update_token_price(
        oracle.oracle.OracleCap[-1],
        oracle.oracle.PriceOracle[-1],
        pool_id,
        int(price * 100)
    )


def reset_lending_info(deployer, liquidator, violator):
    sui_project.active_account(deployer)
    # reset btc price
    manipulate_oracle(deployer, 0, 30000)

    sui_project.active_account(violator)
    violator = sui_project.accounts[violator].account_address
    # get violator user id
    violator_id = interfaces.get_dola_user_id(violator.replace('0x', ''))['dola_user_id']
    lending_info = interfaces.get_user_lending_info(int(violator_id))
    pprint.pp(lending_info)
    if len(lending_info['debt_infos']) > 0:
        #  violator repay all debt
        repay_token(violator, init.usdc())

    #  violator withdraw all collateral
    if len(lending_info['collateral_infos']) > 0:
        lending.portal_withdraw_local(init.btc())

    # liquidator withdraw all reward
    sui_project.active_account(liquidator)
    liquidator = sui_project.accounts[liquidator].account_address
    # get liquidator user id
    liquidator_id = interfaces.get_dola_user_id(liquidator.replace('0x', ''))['dola_user_id']
    lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    pprint.pp(lending_info)
    if len(lending_info['collateral_infos']) > 0:
        lending.portal_withdraw_local(init.usdc())

    if len(lending_info['liquid_asset_infos']) > 0:
        lending.portal_withdraw_local(init.btc())


def basic_liquidate(liquidator, violator):
    # violator supply 1 btc
    supply_token(violator, init.btc(), 1)

    # liquidator supply 100000 usdc
    supply_token(liquidator, init.usdc(), 100000)

    # violator borrow 20000 usdc
    borrow_token(violator, init.usdc(), int(20000 * 1e8))

    # current btc price is 30000 usd
    # manipulate oracle to make btc goes down by 5000
    manipulate_oracle(violator, 0, 25000)

    # liquidate user
    liquidate_user(liquidator, violator, init.btc(), init.usdc(), int(1 * 1e8))

    # print liquidate info


def test_basic_liquidate():
    liquidator = "Oracle"
    deployer = violator = "TestAccount"

    reset_lending_info(deployer, liquidator, violator)
    basic_liquidate(liquidator, violator)
    reset_lending_info(deployer, liquidator, violator)
