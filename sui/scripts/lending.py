import base64
from pprint import pprint

from sui_brownie import CacheObject, ObjectType

import load
from init import claim_test_coin, btc, usdt
from init import coin, pool


def portal_supply(coin_type):
    """
    public entry fun supply<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        ctx: &mut TxContext
    )

    :param coin_type:
    :return: payload
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    account_address = lending_portal.account.account_address
    result = lending_portal.lending.supply(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        0,
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        CacheObject[ObjectType.from_type(coin(coin_type))][account_address][-1],
        ty_args=[coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def core_supply(vaa):
    """
    public entry fun supply(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &mut Storage,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :param vaa:
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()

    lending.wormhole_adapter.supply(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        lending.storage.Storage[-1],
        list(base64.b64decode(vaa)),
    )


def portal_withdraw(coin_type, amount):
    """
    public entry fun withdraw<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u64,
        wormhole_message_fee: Coin<SUI>,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    account_address = lending_portal.account.account_address
    dst_chain = 1

    result = lending_portal.lending.withdraw(
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        dst_chain,
        0,
        amount,
        ty_args=[coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def pool_withdraw(vaa, coin_type):
    """
    public entry fun receive_withdraw<CoinType>(
        _wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :param vaa:
    :return:
    """
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    account_address = wormhole_bridge.account.account_address
    wormhole_bridge.bridge_pool.receive_withdraw(
        wormhole.state.State[-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        list(base64.b64decode(vaa)),
        ty_args=[coin_type]
    )


def core_withdraw(vaa):
    """
    public entry fun withdraw(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()

    result = lending.wormhole_adapter.withdraw(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        0,
        list(base64.b64decode(vaa)),
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def portal_borrow(coin_type, amount):
    """
    public entry fun borrow<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u64,
        wormhole_message_fee: Coin<SUI>,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    account_address = lending_portal.account.account_address
    dst_chain = 1

    result = lending_portal.lending.borrow(
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        dst_chain,
        0,
        amount,
        ty_args=[coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def core_borrow(vaa):
    """
    public entry fun borrow(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()
    account_address = lending.account.account_address

    lending.wormhole_adapter.borrow(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        0,
        list(base64.b64decode(vaa)),
    )


def portal_repay(coin_type):
    """
    public entry fun repay<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        repay_coin: Coin<CoinType>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    account_address = lending_portal.account.account_address

    result = lending_portal.lending.repay(
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        0,
        CacheObject[ObjectType.from_type(coin(coin_type))][account_address][-1],
        ty_args=[coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def core_repay(vaa):
    """
    public entry fun repay(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &mut Storage,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()

    lending.wormhole_adapter.repay(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        lending.storage.Storage[-1],
        list(base64.b64decode(vaa))
    )


def portal_liquidate(debt_coin_type, collateral_coin_type):
    """
    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain: u64,
        wormhole_message_fee: Coin<SUI>,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coin: Coin<DebtCoinType>,
        collateral_pool: &mut Pool<CollateralCoinType>,
        // punished person
        punished: address,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    dst_chain = 1
    account_address = lending_portal.account.account_address
    punished = lending_portal.account.account_address

    result = lending_portal.lending.liquidate(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        dst_chain,
        0,
        CacheObject[ObjectType.from_type(pool(debt_coin_type))][account_address][-1],
        CacheObject[ObjectType.from_type(coin(debt_coin_type))][account_address][-1],
        CacheObject[ObjectType.from_type(pool(collateral_coin_type))][account_address][-1],
        punished,
        ty_args=[debt_coin_type, collateral_coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def core_liquidate(vaa):
    """
    public entry fun liquidate(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()
    account_address = lending.account.account_address

    lending.wormhole_adapter.borrow(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        0,
        list(base64.b64decode(vaa)),
    )


def monitor_supply():
    claim_test_coin(btc())
    vaa = portal_supply(btc())
    core_supply(vaa)
    check_app_storage()


def monitor_withdraw():
    to_core_vaa = portal_withdraw(btc(), 1)
    to_pool_vaa = core_withdraw(to_core_vaa)
    pool_withdraw(to_pool_vaa, btc())


def monitor_borrow():
    vaa = portal_borrow(usdt(), 1)
    core_borrow(vaa)


def monitor_repay():
    vaa = portal_repay(usdt())
    core_repay(vaa)


def monitor_liquidate():
    vaa = portal_liquidate(usdt(), btc())
    core_repay(vaa)


def check_pool_info():
    pool_manager = load.pool_manager_package()
    pool_manager_info = pool_manager.get_object_with_super_detail(pool_manager.pool_manager.PoolManagerInfo[-1])

    print("\n --- app liquidity info ---")
    pprint(pool_manager_info)


def check_app_storage():
    lending = load.lending_package()
    storage = lending.get_object_with_super_detail(lending.storage.Storage[-1])
    print("\n --- app storage info ---")
    pprint(storage)


if __name__ == "__main__":
    # monitor_supply()
    # check_pool_info()
    check_app_storage()
