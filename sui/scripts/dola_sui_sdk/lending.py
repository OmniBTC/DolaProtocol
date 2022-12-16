import base64
from pprint import pprint

from sui_brownie import CacheObject, ObjectType

from dola_sui_sdk import load
from dola_sui_sdk.init import btc, usdt, claim_test_coin
from dola_sui_sdk.init import coin, pool

U64_MAX = 18446744073709551615


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

    lending_portal.lending.supply(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        [],
        0,
        CacheObject[ObjectType.from_type(pool(coin_type))]["Shared"][-1],
        [CacheObject[ObjectType.from_type(coin(coin_type))][account_address][-1]],
        U64_MAX,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def core_supply(vaa):
    """
    public entry fun supply(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :param vaa:
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()

    lending.wormhole_adapter.supply(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        list(base64.b64decode(vaa)),
    )


def portal_withdraw(coin_type, amount):
    """
    public entry fun withdraw<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        receiver: vector<u8>,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    account_address = lending_portal.account.account_address
    dst_chain = 0

    result = lending_portal.lending.withdraw(
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        account_address,
        dst_chain,
        [],
        0,
        amount,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


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
        user_manager_info: &mut UserManagerInfo,
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
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()

    result = lending.wormhole_adapter.withdraw(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        0,
        list(base64.b64decode(vaa)),
    )
    return wormhole_bridge.bridge_core.read_vaa.simulate(
        wormhole_bridge.bridge_core.CoreState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def portal_borrow(coin_type, amount):
    """
    public entry fun borrow<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        receiver: vector<u8>,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    account_address = lending_portal.account.account_address
    dst_chain = 0

    result = lending_portal.lending.borrow(
        CacheObject[ObjectType.from_type(pool(coin_type))][account_address][-1],
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        account_address,
        dst_chain,
        [],
        0,
        amount,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def core_borrow(vaa):
    """
    public entry fun borrow(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
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
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()

    result = lending.wormhole_adapter.borrow(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        0,
        list(base64.b64decode(vaa)),
    )
    return wormhole_bridge.bridge_core.read_vaa.simulate(
        wormhole_bridge.bridge_core.CoreState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def portal_repay(coin_type):
    """
    public entry fun repay<CoinType>(
        pool: &mut Pool<CoinType>,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
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
        [],
        0,
        [CacheObject[ObjectType.from_type(coin(coin_type))][account_address][-1]],
        U64_MAX,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def core_repay(vaa):
    """
    public entry fun repay(
        wormhole_adapter: &WormholeAdapater,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    oracle = load.oracle_package()

    lending.wormhole_adapter.repay(
        lending.wormhole_adapter.WormholeAdapater[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending.storage.Storage[-1],
        list(base64.b64decode(vaa))
    )


def portal_liquidate(debt_coin_type, collateral_coin_type):
    """
    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        receiver: vector<u8>,
        dst_chain: u16,
        wormhole_message_coins: vector<Coin<SUI>>,
        wormhole_message_amount: u64,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coins: vector<Coin<DebtCoinType>>,
        debt_amount: u64,
        liquidate_user_id: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    dst_chain = 0
    account_address = lending_portal.account.account_address

    result = lending_portal.lending.liquidate(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        account_address,
        dst_chain,
        [],
        0,
        CacheObject[ObjectType.from_type(pool(debt_coin_type))][account_address][-1],
        [CacheObject[ObjectType.from_type(coin(debt_coin_type))][account_address][-1]],
        U64_MAX,
        0,
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


def pool_binding(bind_address):
    '''
    public entry fun send_binding(
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        wormhole_message_fee: Coin<SUI>,
        dola_chain_id: u16,
        bind_address: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    '''
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    dola_chain_id = 0

    wormhole_bridge.bridge_pool.send_binding(
        wormhole_bridge.bridge_pool.PoolState[-1],
        wormhole.state.State[-1],
        0,
        dola_chain_id,
        bind_address
    )


def core_binding(vaa):
    '''
    public fun receive_binding(
        _wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        user_manager_info: &mut UserManagerInfo,
        vaa: vector<u8>
    )
    :return:
    '''
    wormhole = load.wormhole_package()
    wormhole_bridge = load.wormhole_bridge_package()
    user_manager = load.user_manager_package()

    wormhole_bridge.bridge_core.receive_binding(
        wormhole.state.State[-1],
        wormhole_bridge.bridge_core.CoreState[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        list(base64.b64decode(vaa))
    )


def export_objects():
    # Package id
    lending_portal = load.lending_portal_package()
    external_interfaces = load.external_interfaces_package()
    wormhole_bridge = load.wormhole_bridge_package()
    print(f"lending_portal={lending_portal.package_id}")
    print(f"external_interfaces={external_interfaces.package_id}")
    print(f"wormhole_bridge={wormhole_bridge.package_id}")

    # objects
    wormhole = load.wormhole_package()
    oracle = load.oracle_package()
    lending = load.lending_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()

    data = {
        "PoolState": wormhole_bridge.bridge_pool.PoolState[-1],
        "WormholeState": wormhole.state.State[-1],
        "PriceOracle": oracle.oracle.PriceOracle[-1],
        "Storage": lending.storage.Storage[-1],
        "PoolManagerInfo": pool_manager.pool_manager.PoolManagerInfo[-1],
        "UserManagerInfo": user_manager.user_manager.UserManagerInfo[-1]
    }
    coin_types = [btc(), usdt()]
    for k in coin_types:
        coin_key = k.split("::")[-1]
        data[coin_key] = k.replace("0x", "")
        dk = f'Pool<{k.split("::")[-1]}>'
        data[dk] = CacheObject[ObjectType.from_type(pool(k))]["Shared"][-1]

    pprint(data)


def monitor_supply(coin):
    vaa = portal_supply(coin)
    # core_supply(vaa)


def monitor_withdraw(coin, amount=1):
    to_core_vaa = portal_withdraw(coin, amount * 1e8)
    # to_pool_vaa = core_withdraw(to_core_vaa)
    # pool_withdraw(to_pool_vaa, coin)


def monitor_borrow(coin, amount=1):
    to_core_vaa = portal_borrow(coin, amount * 1e8)
    # to_pool_vaa = core_borrow(to_core_vaa)
    # pool_withdraw(to_pool_vaa, coin)


def monitor_repay(coin):
    vaa = portal_repay(coin)
    # core_repay(vaa)


def monitor_liquidate():
    vaa = portal_liquidate(usdt(), btc())
    # core_repay(vaa)


def monitor_binding(bind_address):
    pool_binding(bind_address)


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
    # claim_test_coin(btc())
    # monitor_supply(btc())
    check_pool_info()
