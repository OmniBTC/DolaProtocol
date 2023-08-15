from pprint import pprint

import ccxt

import config
import dola_monitor
from dola_sui_sdk import load, sui_project, init


# btc -> dola_pool_id 0
# usdt -> dola_pool_id 1
# sui -> dola_chain_id 0

def parse_u256(data: list):
    output = 0
    for i in range(32):
        output = (output << 8) + int(data[31 - i])
    return output


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
    """
    public entry fun get_all_pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        dola_pool_id: u16
    )
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager = sui_project.network_config['objects']['PoolManagerInfo']
    result = external_interfaces.interfaces.get_all_pool_liquidity.simulate(
        pool_manager,
        dola_pool_id,
    )

    return result['events'][-1]['parsedJson']


def get_all_reserve_info():
    """

    :return:
    """
    external_interfaces = load.external_interfaces_package()

    pool_manager = sui_project.network_config['objects']['PoolManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    result = external_interfaces.interfaces.get_all_reserve_info.inspect(
        pool_manager,
        lending_storage
    )
    pprint(result)
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
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    result = external_interfaces.interfaces.get_user_collateral.inspect(
        lending_storage,
        price_oracle,
        user,
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

    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    result = external_interfaces.interfaces.get_user_lending_info.simulate(
        lending_storage,
        price_oracle,
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


def get_user_allowed_withdraw(dola_chain_id, dola_user_id, dola_pool_id, withdraw_all=False):
    """
    public entry fun get_user_allowed_withdraw(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16,
        dola_user_id: u64,
        withdraw_pool_id: u16,
        withdarw_all: bool,
    )

    :param dola_chain_id:
    :param dola_user_id:
    :param dola_pool_id:
    :return:
    """
    external_interfaces = load.external_interfaces_package()
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    result = external_interfaces.interfaces.get_user_allowed_withdraw.inspect(
        pool_manager_info,
        lending_storage,
        price_oracle,
        dola_chain_id,
        dola_user_id,
        dola_pool_id,
        withdraw_all
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

    result = external_interfaces.interfaces.get_user_allowed_borrow.inspect(
        pool_manager_info,
        lending_storage,
        price_oracle,
        dola_chain_id,
        dola_user_id,
        dola_pool_id
    )

    pprint(result)
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
        True,
        False,
        True,
        False,
        False,
        False,
        False
    )

    return result['events'][-1]['parsedJson']


def reward_claim_inspect(
        dola_pool_id,
        reward_pool,
        reward_action,
):
    dola_protocol = load.dola_protocol_package()
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.lending_portal_v2.claim.inspect(
        user_manager_info,
        lending_storage,
        dola_pool_id,
        reward_action,
        reward_pool,
        clock,
        type_arguments=[init.sui()["coin_type"]]
    )
    return result['events'][-1]['parsedJson']


def get_user_total_reward_info(
        dola_user_id,
        reward_tokens,
        dola_pool_ids,
        reward_pools
):
    external_interface = load.external_interfaces_package()

    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    clock = sui_project.network_config['objects']['Clock']

    result = external_interface.interfaces.get_user_total_reward_info.inspect(
        lending_storage,
        price_oracle,
        dola_user_id,
        reward_tokens,
        dola_pool_ids,
        reward_pools,
        clock
    )
    return result['events'][-1]['parsedJson']


def calculate_apys():
    all_rewards = {
        "sui_otoken_reward": 9877.84 * 0.6 / 7 * 365,
        "whusdc_otoken_reward": 4278.3 * 0.6 / 7 * 365,
        "sui_dtoken_reward": 9877.84 * 0.6 / 7 * 365,
        "whusdc_dtoken_reward": 4278.3 * 0.6 / 7 * 365,
    }

    sui_otoken_value = dola_monitor.get_otoken_total_supply(3) / 1e8 * 0.6
    whusdc_otoken_value = dola_monitor.get_otoken_total_supply(8) / 1e8
    sui_dtoken_value = dola_monitor.get_dtoken_total_supply(3) / 1e8 * 0.6
    whusdc_dtoken_value = dola_monitor.get_dtoken_total_supply(8) / 1e8

    print(
        {
            "sui_otoken_apy": all_rewards["sui_otoken_reward"] / sui_otoken_value,
            "whusdc_otoken_apy": all_rewards["whusdc_otoken_reward"] / whusdc_otoken_value,
            "sui_dtoken_apy": all_rewards["sui_dtoken_reward"] / sui_dtoken_value,
            "whusdc_dtoken_apy": all_rewards["whusdc_dtoken_reward"] / whusdc_dtoken_value,

        }
    )


def get_reward_pool_apys(
        reward_tokens=None,
        reward_pools=None,
        dola_pool_ids=None

):
    if reward_tokens is None:
        reward_tokens = [3, 3, 3, 3]
        reward_pools = [3, 8, 3, 8]
        dola_pool_ids = ["0xda4deae4c153c275dacd1fda66567ab158deac5ce17408a4c343bc8ebf8901cc",
                         "0x290791baf8da8fc0d12be3257acc50bddcf1cfbd72c510d63c27473063f17867",
                         "0x0dece1bbc7977d63394a403166bfad63628a5bc42dde6edc14935159a7824000",
                         "0x18368d5f2bdbb16d3c2135837e91aef85ae372b4df909bc75ad8463faa3a8c45"
                         ]
    external_interface = load.external_interfaces_package()

    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    clock = sui_project.network_config['objects']['Clock']

    result = external_interface.interfaces.get_reward_pool_apys.inspect(
        lending_storage,
        price_oracle,
        reward_tokens,
        dola_pool_ids,
        reward_pools,
        clock
    )
    return result['events'][-1]['parsedJson']


def get_otoken_total_supply(dola_pool_id):
    dola_protocol = load.dola_protocol_package()

    lending_storage = sui_project.network_config['objects']['LendingStorage']

    result = dola_protocol.lending_logic.total_otoken_supply.inspect(
        lending_storage,
        dola_pool_id
    )

    return parse_u256(result['results'][0]['returnValues'][0][0])


def get_protocol_total_otoken_value():
    reserves_ids = list(range(9))

    kucoin = ccxt.kucoin()
    kucoin.load_markets()

    protocol_total_otoken_value = 0

    for pool_id in reserves_ids:
        symbol = config.DOLA_POOL_ID_TO_SYMBOL[pool_id]
        if symbol in ['USDT/USD', 'USDC/USD']:
            price = 1
        else:
            price = kucoin.fetch_ticker(f"{symbol}T")['close']

        total_otoken = get_otoken_total_supply(pool_id)
        value = total_otoken / 1e8 * price
        protocol_total_otoken_value += value

    return protocol_total_otoken_value


if __name__ == "__main__":
    # pprint(get_dola_token_liquidity(1))
    # dola_addresses = get_dola_user_addresses(1)
    # result = [(bytes(data['dola_address']).hex(), data['dola_chain_id']) for data in
    #           dola_addresses['dola_user_addresses']]
    # pprint(get_eq_fee(23, '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8', 15550527))
    # pprint(int(calculate_changed_health_factor(1, 1, int(1e8))['health_factor']) / 1e27)
    # pprint(result)
    # pprint(get_user_all_collateral(1))
    # pprint(get_user_health_factor(1))
    # pprint(get_reserve_info(1))
    # pprint(get_app_token_liquidity(1, 0))
    # pprint(get_all_pool_liquidity(4))
    # pprint(get_user_allowed_borrow("0xdc1f21230999232d6cfc230c4730021683f6546f", 1))
    # pprint(get_user_token_debt("0xdc1f21230999232d6cfc230c4730021683f6546f", 1))
    # pprint(get_user_collateral(66, 3))
    # pprint(get_user_lending_info(6))
    # pprint(get_user_allowed_borrow(0, 1, 3))
    # pprint(get_all_pool_liquidity(1))
    # pprint(get_all_reserve_info())
    # pprint(get_user_allowed_withdraw(23, 1, 2))
    # pprint(reward_claim_inspect(3, "0x1e477aafbdff2e900a1fdc274c3ba34b9dd552f3aaea0dbdeb7c1a4e2c4a2b21", 0))
    get_protocol_total_otoken_value()
    # print(get_reward_pool_apys())
