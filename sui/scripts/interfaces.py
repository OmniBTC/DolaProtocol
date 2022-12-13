import pprint

import init
import load


def get_dola_token_liquidity(catalog):
    """
    public entry fun get_dola_token_liquidity(pool_manager_info: &mut PoolManagerInfo, catalog: String)
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_dola_token_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        list(bytes(catalog.replace("0x", ""), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']


def get_app_token_liquidity(app_id, catalog):
    """
    public entry fun get_app_token_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        app_id: u16,
        catalog: String
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_app_token_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        app_id,
        list(bytes(catalog.replace("0x", ""), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']


def get_user_token_debt(user, catalog):
    """
    public entry fun get_user_token_debt(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: DolaAddress,
        catalog: String
    )
    :param user:
    :param catalog:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_token_debt.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user,
        list(bytes(catalog.replace("0x", ""), 'ascii'))
    )
    return result['events'][-1]['moveEvent']['fields']


def get_user_collateral(user, catalog):
    """
    public entry fun get_user_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: DolaAddress,
        catalog: String
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
        list(bytes(catalog.replace("0x", ""), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']


def get_user_lending_info(user):
    """
    public entry fun get_user_lending_info(storage: &mut Storage, oracle: &mut PriceOracle, user_address: DolaAddress)
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


def get_reserve_info(catalog):
    """
    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        catalog: String
    )
    :param catalog:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_reserve_info.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        lending.storage.Storage[-1],
        list(bytes(catalog.replace("0x", ""), 'ascii'))
    )

    return result['events'][-1]['moveEvent']['fields']


def get_user_allowed_borrow(user, catalog):
    """
    public entry fun get_user_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        borrow_token: vector<u8>,
        user_address: DolaAddress
    )
    :param catalog:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_allowed_borrow.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        list(bytes(catalog.replace("0x", ""), 'ascii')),
        user
    )

    return result['events'][-1]['moveEvent']['fields']


if __name__ == "__main__":
    pprint.pp(get_dola_token_liquidity(init.usdt()))
