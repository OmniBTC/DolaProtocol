from dola_sui_sdk import lending, init, interfaces, load, sui_project


def parse_u256(data: list):
    output = 0
    for i in range(32):
        output = (output << 8) + int(data[31 - i])
    return output


def get_liquidation_discount(liquidator_id, violator_id):
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    result = lending_core.logic.calculate_liquidation_discount.inspect(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        int(liquidator_id),
        int(violator_id)
    )
    return parse_u256(result['results'][0]['returnValues'][0][0])


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

    # check lending info before liquidation
    liquidator = sui_project.accounts[liquidator].account_address
    violator = sui_project.accounts[violator].account_address
    liquidator_id = interfaces.get_dola_user_id(liquidator.replace('0x', ''))['dola_user_id']
    violator_id = interfaces.get_dola_user_id(violator.replace('0x', ''))['dola_user_id']
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    liquidation_discount = round(get_liquidation_discount(liquidator_id, violator_id) / 1e25, 2)
    before_total_collateral_value = liquidator_lending_info['total_collateral_value']
    before_violator_collateral = violator_lending_info['total_collateral_value']
    before_total_liquid_asset_value = liquidator_lending_info['total_liquid_value']

    # liquidate user
    liquidate_user(liquidator, violator, init.btc(), init.usdc(), int(1 * 1e8))

    # check after lending info after liquidation
    lending_info = interfaces.get_user_lending_info(int(liquidator_id))

    after_total_collateral_value = lending_info['total_collateral_value']
    after_violator_collateral = violator_lending_info['total_collateral_value']
    after_total_liquid_asset_value = lending_info['total_liquid_value']

    liquidation_ratio = round(
        (before_violator_collateral - after_violator_collateral) / before_total_collateral_value * 100, 2)
    repaid_debt = round((before_total_collateral_value - after_total_collateral_value) / 1e8, 2)
    harvested_collateral = round((after_total_liquid_asset_value - before_total_liquid_asset_value) / 1e8, 2)

    print("Liquidation Info")
    print(f"Liquidator: {liquidator} -- Violator: {violator}")
    print(f"Liquidator repaid debt value: $ {repaid_debt} ")
    print(f"Liquidator harvested value of the collateral: $ {harvested_collateral} ")
    print(f"Liquidator reward: $ {harvested_collateral - repaid_debt} ")
    print(f"Liquidation ratio: {liquidation_ratio} %")
    print(f"Liquidation discount: {liquidation_discount} % ")


# def test_basic_liquidate():
#     liquidator = "Oracle"
#     deployer = violator = "TestAccount"
#
#     reset_lending_info(deployer, liquidator, violator)
#     basic_liquidate(liquidator, violator)
#     reset_lending_info(deployer, liquidator, violator)


if __name__ == '__main__':
    liquidator = "Oracle"
    deployer = violator = "TestAccount"
    basic_liquidate(liquidator, violator)
