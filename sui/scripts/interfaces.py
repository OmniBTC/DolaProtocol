import init
import load


def get_dora_token_liquidity(token_name):
    """
    public entry fun get_dora_token_liquidity(pool_manager_info: &mut PoolManagerInfo, token_name: vector<u8>)
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_dora_token_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        list(bytes(token_name.strip("0x"), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']['token_liquidity']


def get_app_token_liquidity(app_id, token_name):
    """
    public entry fun get_app_token_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        app_id: u16,
        token_name: vector<u8>
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_app_token_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        app_id,
        list(bytes(token_name.strip("0x"), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']['token_liquidity']


def get_user_token_debt(user, token_name):
    """
    public entry fun get_user_token_debt(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>
    )
    :param user:
    :param token_name:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_token_debt.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user,
        list(bytes(token_name.strip("0x"), 'ascii'))
    )
    debt_amount = result['events'][-1]['moveEvent']['fields']['debt_amount']
    debt_value = result['events'][-1]['moveEvent']['fields']['debt_value'] / 1e8
    return (debt_amount, debt_value)


def get_user_collateral(user, token_name):
    """
    public entry fun get_user_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_collateral.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user,
        list(bytes(token_name.strip("0x"), 'ascii'))
    )
    collateral_amount = result['events'][-1]['moveEvent']['fields']['collateral_amount']
    collateral_value = result['events'][-1]['moveEvent']['fields']['collateral_value'] / 1e8
    return (collateral_amount, collateral_value)


def get_user_lending_info(user):
    """
    public entry fun get_user_lending_info(storage: &mut Storage, oracle: &mut PriceOracle, user_address: vector<u8>)
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_lending_info.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user
    )
    return result['events'][-1]['moveEvent']['fields']


def get_reserve_info(token_name):
    """
    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        token_name: vector<u8>
    )
    :param token_name:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_reserve_info.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        lending.storage.Storage[-1],
        list(bytes(token_name.strip("0x"), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']


if __name__ == "__main__":
    print(get_reserve_info(init.btc()))
