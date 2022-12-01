import base64
from pprint import pprint

from sui_brownie import CacheObject, ObjectType

from scripts.python import load
from scripts.python.init import coin, sui, pool, usdt, mint_and_transfer_test_coin


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
    result = lending_portal.lending.supply(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        CacheObject[ObjectType.from_type(coin(sui()))][-1],
        CacheObject[ObjectType.from_type(pool(coin_type))][-1],
        CacheObject[ObjectType.from_type(coin(coin_type))][-1],
        ty_args=[coin_type]
    )
    pprint(result)


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
    dst_chain = 1

    result = lending_portal.lending.withdraw(
        CacheObject[ObjectType.from_type(pool(coin_type))][-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        dst_chain,
        CacheObject[ObjectType.from_type(coin(sui()))][-1],
        amount,
        ty_args=[coin_type]
    )
    pprint(result)


def test_supply():
    mint_and_transfer_test_coin(usdt(), 1e8)
    portal_supply(usdt())


def test_withdraw():
    portal_withdraw(usdt())
