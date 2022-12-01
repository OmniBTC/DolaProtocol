import base64

from sui_brownie import CacheObject, ObjectType

from scripts.python import load
from scripts.python.init import coin, sui, pool, usdt, mint_and_transfer_test_coin, xbtc


def portal_supply(coin_type):
    '''
    public entry fun supply<CoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        ctx: &mut TxContext
    )

    :param cointype:
    :return: payload
    '''
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    account_address = lending_portal.account.account_address
    result = lending_portal.lending.supply(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        CacheObject[ObjectType.from_type(coin(coin_type))][account_address][-1],
        ty_args=[coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


def core_supply(vaa):
    '''
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
    '''
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
    '''
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
    '''
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
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
        amount,
        ty_args=[coin_type]
    )
    return result['events'][-1]['moveEvent']['fields']['payload']


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
    account_address = lending.account.account_address

    lending.wormhole_adapter.withdraw(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
        list(base64.b64decode(vaa)),
    )


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
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
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
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
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
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
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
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
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
        CacheObject[ObjectType.from_type(coin(sui()))][account_address][-1],
        list(base64.b64decode(vaa)),
    )


def test_supply():
    mint_and_transfer_test_coin(xbtc(), 1e8)
    vaa = portal_supply(xbtc())
    core_supply(vaa)


def test_withdraw():
    portal_withdraw(xbtc())


def test_borrow():
    portal_borrow(usdt(), 1e8)


def test_repay():
    portal_repay(usdt())


def test_liquidate():
    portal_liquidate(usdt(), xbtc())
