from dola_sui_sdk import lending, init, interfaces, load, sui_project


# Dola pools id:
#  - 0: BTC
#  - 1: USDT
#  - 2: USDC

# There 4 actor in this test:
#  - Saver: Providing liquidity to the pool, ensuring that there are tokens to borrow.
#  - Violator: Borrowing tokens from the pool, health factor below 1 is liquidated.
#  - Liquidator: Liquidating the violator, getting a discount on the collateral.
#  - Deployer: Have capability to manipulate oracle prices in test.

def parse_u256(data: list):
    output = 0
    for i in range(32):
        output = (output << 8) + int(data[31 - i])
    return output


def get_pool_address(pool_id):
    if pool_id == 0:
        return init.btc()
    elif pool_id == 1:
        return init.usdt()
    else:
        return init.usdc()


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


def get_treasury_debt(token):
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()

    result = lending_core.logic.user_loan_value.inspect(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        0,
        int(token)
    )
    return parse_u256(result['results'][0]['returnValues'][0][0])


def get_treasury_collateral(token):
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()

    result = lending_core.logic.user_collateral_value.inspect(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        0,
        int(token)
    )
    return parse_u256(result['results'][0]['returnValues'][0][0])


def get_faucet_admins():
    test_coins = load.test_coins_package()
    result = sui_project.client.sui_getObject(test_coins.faucet.Faucet[-1], {
        "showType": False,
        "showOwner": False,
        "showPreviousTransaction": False,
        "showDisplay": False,
        "showContent": True,
        "showBcs": False,
        "showStorageRebate": False
    })
    return result['data']['content']['fields']['admins']['fields']['contents']


def set_mint_cap(user):
    sui_project.active_account("TestAccount")
    admin = sui_project.accounts[user].account_address
    init.add_test_coins_admin(admin)


def supply_token(token, amount):
    init.force_claim_test_coin(token, amount)
    lending.portal_supply(token)


def borrow_token(token, amount):
    lending.portal_borrow_local(token, amount)


def repay_token(token, repay_amount):
    init.force_claim_test_coin(token, int(repay_amount / 1e8))
    lending.portal_repay(token)
    lending.portal_withdraw_local(token)


def liquidate_user(violator, collateral, debt, deposit_amount):
    violator_address = sui_project.accounts[violator].account_address
    # get violator user id
    violator_id = interfaces.get_dola_user_id(violator_address.replace('0x', ''))['dola_user_id']
    init.force_claim_test_coin(debt, deposit_amount)
    lending.portal_liquidate(debt, int(deposit_amount * 1e8), collateral, 0, violator_id)


def manipulate_oracle(pool_id, price):
    oracle = load.oracle_package()
    oracle.oracle.update_token_price(
        oracle.oracle.OracleCap[-1],
        oracle.oracle.PriceOracle[-1],
        pool_id,
        int(price * 100)
    )


def saver_supply(saver):
    sui_project.active_account(saver)

    # supply 100 btc
    init.force_claim_test_coin(init.btc(), 100)
    lending.portal_supply(init.btc())

    # supply 100000 usdt
    init.force_claim_test_coin(init.usdt(), 100000)
    lending.portal_supply(init.usdt())

    # supply 100000 usdc
    init.force_claim_test_coin(init.usdc(), 100000)
    lending.portal_supply(init.usdc())


def reset_oracle_price(deployer):
    sui_project.active_account(deployer)
    # reset btc price
    manipulate_oracle(0, 30000)


def reset_lending_info(user):
    sui_project.active_account(user)
    user_address = sui_project.accounts[user].account_address
    user_id = interfaces.get_dola_user_id(user_address.replace('0x', ''))['dola_user_id']
    lending_info = interfaces.get_user_lending_info(int(user_id))

    for debt_info in lending_info['debt_infos']:
        dola_pool_id = int(debt_info['dola_pool_id'])
        token = get_pool_address(dola_pool_id)
        repay_token(token, int(debt_info['debt_amount']) * 2)

    for collateral_info in lending_info['collateral_infos']:
        dola_pool_id = int(collateral_info['dola_pool_id'])
        token = get_pool_address(dola_pool_id)
        lending.portal_withdraw_local(token)

    for liquid_info in lending_info['liquid_asset_infos']:
        dola_pool_id = int(liquid_info['dola_pool_id'])
        token = get_pool_address(dola_pool_id)
        lending.portal_withdraw_local(token)


def basic_liquidate(deployer, liquidator, violator):
    # liquidator supply 20000 usdc
    sui_project.active_account(liquidator)
    supply_token(init.usdc(), 20000)

    # violator supply 1 btc
    sui_project.active_account(violator)
    supply_token(init.btc(), 1)

    # violator borrow 20000 usdc
    borrow_token(init.usdc(), int(20000 * 1e8))

    # current btc price is 30000 usd
    # manipulate oracle to make btc goes down by 5000
    sui_project.active_account(deployer)
    manipulate_oracle(0, 25000)

    # check lending info before liquidation
    liquidator_address = sui_project.accounts[liquidator].account_address
    violator_address = sui_project.accounts[violator].account_address
    liquidator_id = interfaces.get_dola_user_id(liquidator_address.replace('0x', ''))['dola_user_id']
    violator_id = interfaces.get_dola_user_id(violator_address.replace('0x', ''))['dola_user_id']
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    liquidation_discount = round(get_liquidation_discount(liquidator_id, violator_id) / 1e25, 2)
    before_violator_collateral = int(violator_lending_info['collateral_infos'][0]['collateral_amount'])
    before_total_liquid_asset_value = int(liquidator_lending_info['total_liquid_value'])
    before_total_collateral_value = int(liquidator_lending_info['total_collateral_value'])
    before_violator_hf = (int(violator_lending_info['health_factor']) / 1e27, 2)

    # liquidate user
    # liquidator use 20000 usdc to liquidate violator
    liquidate_user(violator, init.btc(), init.usdc(), 0)

    # check after lending info after liquidation
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    after_total_collateral_value = int(liquidator_lending_info['total_collateral_value'])
    after_violator_collateral = int(violator_lending_info['collateral_infos'][0]['collateral_amount'])
    after_total_liquid_asset_value = int(liquidator_lending_info['total_liquid_value'])
    after_violator_hf = (int(violator_lending_info['health_factor']) / 1e27, 2)

    liquidation_ratio = round(
        ((before_violator_collateral - after_violator_collateral) / before_violator_collateral) * 100, 2)
    repaid_debt = round((before_total_collateral_value - after_total_collateral_value) / 1e8, 2)
    harvested_collateral = round((after_total_liquid_asset_value - before_total_liquid_asset_value) / 1e8, 2)

    print("Liquidation Info")
    print(f"Liquidator: {liquidator} -- Violator: {violator}")
    print(f"Liquidator repaid debt value: {repaid_debt} $")
    print(f"Liquidator harvested value of the collateral: {harvested_collateral} $ ")
    print(f"Liquidator reward: {harvested_collateral - repaid_debt} $")
    print(f"Liquidation ratio: {liquidation_ratio} %")
    print(f"Liquidation discount: {liquidation_discount} % ")
    print(f"Violator health factor: {before_violator_hf} -> {after_violator_hf}")


def liquidate_with_temporarily_collateral(deployer, liquidator, violator):
    # violator supply 1 btc
    sui_project.active_account(violator)
    supply_token(init.btc(), 1)

    # violator borrow 20000 usdc
    borrow_token(init.usdc(), int(20000 * 1e8))

    # current btc price is 30000 usd
    # manipulate oracle to make btc goes down by 5000
    sui_project.active_account(deployer)
    manipulate_oracle(0, 25000)

    # check lending info before liquidation
    liquidator_address = sui_project.accounts[liquidator].account_address
    violator_address = sui_project.accounts[violator].account_address
    liquidator_id = interfaces.get_dola_user_id(liquidator_address.replace('0x', ''))['dola_user_id']
    violator_id = interfaces.get_dola_user_id(violator_address.replace('0x', ''))['dola_user_id']
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    liquidation_discount = round(get_liquidation_discount(liquidator_id, violator_id) / 1e25, 2)
    before_violator_collateral = int(violator_lending_info['collateral_infos'][0]['collateral_amount'])
    before_total_liquid_asset_value = int(liquidator_lending_info['total_liquid_value'])
    before_violator_hf = (int(violator_lending_info['health_factor']) / 1e27, 2)

    # liquidate user
    sui_project.active_account(liquidator)
    # liquidator use 20000 usdc to liquidate violator
    repay_amount = 20000
    liquidate_user(violator, init.btc(), init.usdc(), repay_amount)

    # check after lending info after liquidation
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    after_total_collateral_value = int(liquidator_lending_info['total_collateral_value'])
    after_violator_collateral = int(violator_lending_info['collateral_infos'][0]['collateral_amount'])
    after_total_liquid_asset_value = int(liquidator_lending_info['total_liquid_value'])
    after_violator_hf = (int(violator_lending_info['health_factor']) / 1e27, 2)

    liquidation_ratio = round(
        ((before_violator_collateral - after_violator_collateral) / before_violator_collateral) * 100, 2)

    repay_value = int(repay_amount * 1e8)
    repaid_debt = round((repay_value - after_total_collateral_value) / 1e8, 2)
    harvested_collateral = round((after_total_liquid_asset_value - before_total_liquid_asset_value) / 1e8, 2)

    print("Liquidation Info")
    print(f"Liquidator: {liquidator} -- Violator: {violator}")
    print(f"Liquidator repaid debt value: {repaid_debt} $")
    print(f"Liquidator harvested value of the collateral: {harvested_collateral} $ ")
    print(f"Liquidator reward: {harvested_collateral - repaid_debt} $")
    print(f"Liquidation ratio: {liquidation_ratio} %")
    print(f"Liquidation discount: {liquidation_discount} % ")
    print(f"Violator health factor: {before_violator_hf} -> {after_violator_hf}")


def liquidate_partial_collateral(deployer, liquidator, violator):
    # liquidator supply 10000 usdc
    sui_project.active_account(liquidator)
    supply_token(init.usdc(), 10000)

    # violator supply 1 btc
    sui_project.active_account(violator)
    supply_token(init.btc(), 1)

    # violator borrow 20000 usdc
    borrow_token(init.usdc(), int(20000 * 1e8))

    # current btc price is 30000 usd
    # manipulate oracle to make btc goes down by 5000
    sui_project.active_account(deployer)
    manipulate_oracle(0, 25000)

    # check lending info before liquidation
    liquidator_address = sui_project.accounts[liquidator].account_address
    violator_address = sui_project.accounts[violator].account_address
    liquidator_id = interfaces.get_dola_user_id(liquidator_address.replace('0x', ''))['dola_user_id']
    violator_id = interfaces.get_dola_user_id(violator_address.replace('0x', ''))['dola_user_id']
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    liquidation_discount = round(get_liquidation_discount(liquidator_id, violator_id) / 1e25, 2)
    before_violator_collateral = int(violator_lending_info['collateral_infos'][0]['collateral_amount'])
    before_total_liquid_asset_value = int(liquidator_lending_info['total_liquid_value'])
    before_total_collateral_value = int(liquidator_lending_info['total_collateral_value'])
    before_violator_hf = (int(violator_lending_info['health_factor']) / 1e27, 2)

    # liquidate user
    # liquidator use 10000 usdc to liquidate violator
    liquidate_user(violator, init.btc(), init.usdc(), 0)

    # check after lending info after liquidation
    liquidator_lending_info = interfaces.get_user_lending_info(int(liquidator_id))
    violator_lending_info = interfaces.get_user_lending_info(int(violator_id))

    after_total_collateral_value = int(liquidator_lending_info['total_collateral_value'])
    after_violator_collateral = int(violator_lending_info['collateral_infos'][0]['collateral_amount'])
    after_total_liquid_asset_value = int(liquidator_lending_info['total_liquid_value'])
    after_violator_hf = (int(violator_lending_info['health_factor']) / 1e27, 2)

    liquidation_ratio = round(
        ((before_violator_collateral - after_violator_collateral) / before_violator_collateral) * 100, 2)
    repaid_debt = round((before_total_collateral_value - after_total_collateral_value) / 1e8, 2)
    harvested_collateral = round((after_total_liquid_asset_value - before_total_liquid_asset_value) / 1e8, 2)

    print("Liquidation Info")
    print(f"Liquidator: {liquidator} -- Violator: {violator}")
    print(f"Liquidator repaid debt value: {repaid_debt} $")
    print(f"Liquidator harvested value of the collateral: {harvested_collateral} $ ")
    print(f"Liquidator reward: {harvested_collateral - repaid_debt} $")
    print(f"Liquidation ratio: {liquidation_ratio} %")
    print(f"Liquidation discount: {liquidation_discount} % ")
    print(f"Violator health factor: {before_violator_hf} -> {after_violator_hf}")


def liquidate_multi_asset():
    pass


def liquidate_cover_liquidator_debt():
    pass


def liquidate_with_deficit():
    pass


def check_faucet_admins(saver, liquidator, violator):
    faucet_admins = get_faucet_admins()
    saver_address = sui_project.accounts[saver].account_address
    if saver_address not in faucet_admins:
        set_mint_cap(saver)

    liquidator_address = sui_project.accounts[liquidator].account_address
    if liquidator_address not in faucet_admins:
        set_mint_cap(liquidator)

    violator_address = sui_project.accounts[violator].account_address
    if violator_address not in faucet_admins:
        set_mint_cap(violator)


def check_saver_supply(saver):
    saver_address = sui_project.accounts[saver].account_address
    try:
        saver_id = interfaces.get_dola_user_id(saver_address.replace('0x', ''))['dola_user_id']
        saver_lending_info = interfaces.get_user_lending_info(int(saver_id))
        if len(saver_lending_info['collateral_infos']) != 3:
            saver_supply(saver)
    except Exception:
        print("Saver not exist")
        saver_supply(saver)


def check_user_init_state(user):
    user_address = sui_project.accounts[user].account_address
    user_id = interfaces.get_dola_user_id(user_address.replace('0x', ''))['dola_user_id']
    user_lending_info = interfaces.get_user_lending_info(int(user_id))

    if len(user_lending_info['collateral_infos']) != 0 or len(user_lending_info['debt_infos']) != 0 \
            or len(user_lending_info['liquid_asset_infos']) != 0:
        reset_lending_info(user)


def check_oracle_price(deployer):
    oracle = load.oracle_package()
    result = oracle.oracle.get_token_price.inspect(
        oracle.oracle.PriceOracle[-1],
        0
    )
    price = int(parse_u256(result['results'][0]['returnValues'][0][0]) / 100)
    if price != 30000:
        reset_oracle_price(deployer)


def check_account_balance(account):
    sui_project.active_account(account)
    sui_coins = sui_project.get_account_sui()
    if len(sui_coins) > 1:
        sui_project.pay_all_sui()
        sui_coins = sui_project.get_account_sui()
    assert int(list(sui_coins.values())[0]['balance']) > int(1e9)


def check_accounts_balance(deployer, saver, liquidator, violator):
    check_account_balance(deployer)
    check_account_balance(saver)
    check_account_balance(liquidator)
    check_account_balance(violator)


def liquidate_init_checks(deployer, saver, liquidator, violator):
    check_accounts_balance(deployer, saver, liquidator, violator)
    check_faucet_admins(saver, liquidator, violator)
    check_saver_supply(saver)
    check_oracle_price(deployer)
    check_user_init_state(liquidator)
    check_user_init_state(violator)


liquidator = "Oracle"
deployer = violator = "TestAccount"
saver = "Relayer1"


def test_basic_liquidate():
    liquidate_init_checks(deployer, saver, liquidator, violator)
    basic_liquidate(deployer, liquidator, violator)


def test_liquidate_with_temporarily_collateral():
    liquidate_init_checks(deployer, saver, liquidator, violator)
    liquidate_with_temporarily_collateral(deployer, liquidator, violator)


def test_liquidate_partial_collateral():
    liquidate_init_checks(deployer, saver, liquidator, violator)
    liquidate_partial_collateral(deployer, liquidator, violator)


if __name__ == '__main__':
    liquidator = "Oracle"
    deployer = violator = "TestAccount"
    saver = "Relayer1"
    init.force_claim_test_coin(init.btc(), 0)
