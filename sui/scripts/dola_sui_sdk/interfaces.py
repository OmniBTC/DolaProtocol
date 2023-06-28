from pprint import pprint

from dola_sui_sdk import load, sui_project


# btc -> dola_pool_id 0
# usdt -> dola_pool_id 1
# sui -> dola_chain_id 0

def get_dola_token_liquidity(dola_pool_id):
    """
    public entry fun get_dola_token_liquidity(pool_manager_info: &mut PoolManagerInfo, dola_pool_id: u16)
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_dola_token_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        dola_pool_id
    )

    return result['events'][-1]['parsedJson']


def get_dola_user_id(user_address, dola_chain_id=0):
    """
    public entry fun get_dola_user_id(user_manager_info: &mut UserManagerInfo, dola_chain_id: u16, user: vector<u8>)
    :param dola_chain_id:
    :param user_address:
    :return:
    """
    external_interfaces = load.external_interfaces_package()

    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    result = external_interfaces.interfaces.get_dola_user_id.inspect(
        user_manager_info,
        dola_chain_id,
        list(bytes.fromhex(user_address))
    )
    return result['events'][-1]['parsedJson']


def get_dola_user_addresses(dola_user_id):
    '''
    public entry fun get_dola_user_addresses(
        user_manager_info: &mut UserManagerInfo,
        dola_user_id: u64
    )
    :return:
    '''
    external_interfaces = load.external_interfaces_package()

    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    result = external_interfaces.interfaces.get_dola_user_addresses.inspect(
        user_manager_info,
        dola_user_id
    )

    return result['events'][-1]['parsedJson']


def get_app_token_liquidity(app_id, dola_pool_id):
    """
    public entry fun get_app_token_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        app_id: u16,
        dola_pool_id: u16
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_app_token_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        app_id,
        dola_pool_id
    )

    return result['events'][-1]['parsedJson']


def get_pool_liquidity(dola_chain_id, pool_address):
    '''
    public entry fun get_pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        dola_chain_id: u16,
        pool_address: vector<u8>
    )
    :return:
    '''
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_pool_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        dola_chain_id,
        pool_address
    )

    return result['events'][-1]['parsedJson']


def get_all_pool_liquidity(dola_pool_id):
    '''
    public entry fun get_all_pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        dola_pool_id: u16
    )
    :return:
    '''
    external_interfaces = load.external_interfaces_package()
    pool_manager = load.pool_manager_package()
    result = external_interfaces.interfaces.get_all_pool_liquidity.simulate(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        dola_pool_id,
    )

    return result['events'][-1]['parsedJson']


def get_user_health_factor(dola_user_id):
    '''
    public entry fun get_user_health_factor(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    )
    :return:
    '''
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()
    oracle = load.oracle_package()

    result = external_interfaces.interfaces.get_user_health_factor.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_user_id
    )
    return result['events'][-1]['parsedJson']


def get_user_all_debt(dola_user_id):
    '''
    public entry fun get_user_all_debt(storage: &mut Storage, dola_user_id: u64)
    :return:
    '''
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()

    result = external_interfaces.interfaces.get_user_all_debt.simulate(
        lending.storage.Storage[-1],
        dola_user_id
    )
    return result['events'][-1]['parsedJson']


def get_user_token_debt(user, dola_pool_id):
    """
    public entry fun get_user_token_debt(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_manager_info: &mut UserManagerInfo,
        user_address: vector<u8>,
        dola_chain_id: u16,
        dola_pool_id: u16
    )
    :param user:
    :param token_name:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    user_manager = load.user_manager_package()
    lending = load.lending_package()
    oracle = load.oracle_package()

    result = external_interfaces.interfaces.get_user_token_debt.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        user,
        0,
        dola_pool_id
    )
    return result['events'][-1]['parsedJson']


def get_user_all_collateral(dola_user_id):
    '''
    public entry fun get_user_all_collateral(storgae: &mut Storage, dola_user_id: u64)
    :return:
    '''
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_package()

    result = external_interfaces.interfaces.get_user_all_debt.simulate(
        lending.storage.Storage[-1],
        dola_user_id
    )
    return result['events'][-1]['parsedJson']


def get_user_collateral(user, dola_pool_id):
    """
    public entry fun get_user_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_manager_info: &mut UserManagerInfo,
        user_address: vector<u8>,
        dola_chain_id: u16,
        dola_pool_id: u16
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    user_manager = load.user_manager_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_collateral.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        user,
        0,
        dola_pool_id
    )

    return result['events'][-1]['parsedJson']


def get_user_lending_info(user):
    """
    public entry fun get_user_lending_info(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    lending = load.lending_core_package()
    oracle = load.oracle_package()
    result = external_interfaces.interfaces.get_user_lending_info.simulate(
        lending.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        user,
    )

    return result['events'][-1]['parsedJson']


def get_reserve_info(dola_pool_id):
    """
    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16
    )
    :param dola_pool_id:
    :return:
    """
    external_interfaces = load.external_interfaces_package()

    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']

    result = external_interfaces.interfaces.get_reserve_info.inspect(
        pool_manager_info,
        lending_storage,
        dola_pool_id
    )

    return result['events'][-1]['parsedJson']


def get_user_allowed_borrow(dola_chain_id, dola_user_id, dola_pool_id):
    """
    public entry fun get_user_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16,
        dola_user_id: u64,
        borrow_pool_id: u16
    )
    :param token_name:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    result = external_interfaces.interfaces.get_user_allowed_borrow.simulate(
        pool_manager_info,
        lending_storage,
        price_oracle,
        dola_chain_id,
        dola_user_id,
        dola_pool_id
    )

    return result['events'][-1]['parsedJson']


def get_user_total_allowed_borrow(dola_user_id):
    """
        public entry fun get_user_total_allowed_borrow(
            pool_manager_info: &mut PoolManagerInfo,
            storage: &mut Storage,
            oracle: &mut PriceOracle,
            dola_user_id: u64,
        )
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    result = external_interfaces.interfaces.get_user_total_allowed_borrow.inspect(
        pool_manager_info,
        lending_storage,
        price_oracle,
        dola_user_id
    )

    return result['events'][-1]['parsedJson']


def get_eq_fee(dola_chain_id, pool_address, withdraw_amount):
    external_interface = load.external_interfaces_package()

    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']

    result = external_interface.interfaces.get_equilibrium_fee.inspect(
        pool_manager_info,
        dola_chain_id,
        list(bytes.fromhex(pool_address.replace('0x', ''))),
        withdraw_amount
    )

    return result['events'][-1]['parsedJson']


def calculate_changed_health_factor(dola_user_id, dola_pool_id, amount):
    external_interface = load.external_interfaces_package()

    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    result = external_interface.interfaces.calculate_changed_health_factor.inspect(
        lending_storage,
        price_oracle,
        dola_user_id,
        dola_pool_id,
        amount,
        False,
        False,
        False,
        True,
        False,
        False
    )

    return result['events'][-1]['parsedJson']


if __name__ == "__main__":
    # pprint.pp(get_dola_token_liquidity(1))
    # dola_addresses = get_dola_user_addresses(1)
    # result = [(bytes(data['dola_address']).hex(), data['dola_chain_id']) for data in
    #           dola_addresses['dola_user_addresses']]
    # pprint(get_eq_fee(23, '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8', 15550527))
    # pprint(int(calculate_changed_health_factor(1, 1, int(1e8))['health_factor']) / 1e27)
    # pprint.pp(result)
    # pprint.pp(get_user_all_collateral(1))
    # pprint.pp(get_user_health_factor(1))
    # pprint.pp(get_reserve_info(1))
    # pprint.pp(get_app_token_liquidity(1, 0))
    # pprint.pp(get_all_pool_liquidity(4))
    # pprint.pp(get_user_allowed_borrow("0xdc1f21230999232d6cfc230c4730021683f6546f", 1))
    # pprint.pp(get_user_token_debt("0xdc1f21230999232d6cfc230c4730021683f6546f", 1))
    # pprint.pp(get_user_collateral("0xdc1f21230999232d6cfc230c4730021683f6546f", 0))
    # pprint.pp(get_user_lending_info(6))
    # pprint(get_user_allowed_borrow(5, 1, 1))
    pprint(get_user_total_allowed_borrow(1))
