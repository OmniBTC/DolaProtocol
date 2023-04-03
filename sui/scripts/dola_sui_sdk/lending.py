from pprint import pprint

from dola_sui_sdk import load
from dola_sui_sdk.init import btc, usdt, usdc, sui, clock
from dola_sui_sdk.init import coin, pool, bridge_pool_read_vaa
from dola_sui_sdk.load import sui_project
from sui_brownie import SuiObject

U64_MAX = 18446744073709551615


def calculate_sui_gas(gas_used):
    return int(gas_used['computationCost']) + int(gas_used['storageCost']) - int(
        gas_used['storageRebate'])


def portal_as_collateral(pool_ids=None):
    """
    public entry fun as_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        dola_pool_ids: vector<u16>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    if pool_ids is None:
        pool_ids = []

    dola_portal.lending.as_collateral(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_portal.lending.LendingPortal[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        pool_ids
    )


def portal_cancel_as_collateral(pool_ids=None):
    """
    public entry fun cancel_as_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        dola_pool_ids: vector<u16>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    if pool_ids is None:
        pool_ids = []

    dola_portal.lending.cancel_as_collateral(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_portal.lending.LendingPortal[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        pool_ids
    )


def portal_supply(coin_type):
    """
    public entry fun supply<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        deposit_coins: vector<Coin<CoinType>>,
        deposit_amount: u64,
        ctx: &mut TxContext
    )
    :param coin_type:
    :return: payload
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    account_address = dola_portal.account.account_address

    dola_portal.lending.supply(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_portal.lending.LendingPortal[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        sui_project[SuiObject.from_type(pool(coin_type))]["Shared"][-1],
        [sui_project[SuiObject.from_type(
            coin(coin_type))][account_address][-1]],
        U64_MAX,
        type_arguments=[coin_type]
    )


def core_supply(vaa, relay_fee=0):
    """
    public entry fun supply(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :param relay_fee:
    :param vaa:
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = lending_core.wormhole_adapter.supply.simulate(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        vaa,
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])

    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.supply(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            vaa,
        )
    return gas, executed


def portal_withdraw_local(coin_type, amount):
    """
    public entry fun withdraw_local<CoinType>(
        pool_approval: &PoolApproval,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    omnipool = load.omnipool_package()
    account_address = dola_portal.account.account_address

    dola_portal.lending.withdraw_local(
        omnipool.dola_pool.PoolApproval[-1],
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_portal.lending.LendingPortal[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        sui_project[SuiObject.from_type(
            pool(coin_type))][account_address][-1],
        int(amount),
        type_arguments=[coin_type]
    )


def portal_withdraw_remote(pool_addr, amount, relay_fee=0, dst_chain=0, receiver=None):
    """
    public entry fun withdraw_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        lending_portal: &mut LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        relay_fee_coins: vector<Coin<SUI>>,
        relay_fee_amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        assert dst_chain == 0
        receiver = account_address

    dola_portal.lending.withdraw_remote(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        dola_portal.lending.LendingPortal[-1],
        wormhole.state.State[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        list(pool_addr),
        receiver,
        dst_chain,
        int(amount),
        [],
        0,
    )


def pool_withdraw(vaa, coin_type):
    """
    public entry fun receive_withdraw<CoinType>(
        _wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :param coin_type:
    :param vaa:
    :return:
    """
    wormhole = load.wormhole_package()
    omnipool = load.omnipool_package()
    account_address = omnipool.account.account_address
    omnipool.wormhole_adapter_pool.receive_withdraw(
        wormhole.state.State[-1],
        omnipool.wormhole_adapter_pool.PoolState[-1],
        sui_project[SuiObject.from_type(
            pool(coin_type))][account_address][-1],
        vaa,
        type_arguments=[coin_type]
    )


def core_withdraw(vaa, relay_fee=0):
    """
    public entry fun withdraw(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = sui_project.pay_sui([0])
    zero_coin = result['objectChanges'][-1]['objectId']

    result = lending_core.wormhole_adapter.withdraw.simulate(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        zero_coin,
        vaa,
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.withdraw(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            zero_coin,
            vaa,
        )

    return gas, executed


def portal_borrow_local(coin_type, amount):
    """
    public entry fun borrow_local<CoinType>(
        pool_approval: &PoolApproval,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    omnipool = load.omnipool_package()
    account_address = dola_portal.account.account_address

    dola_portal.lending.borrow_local(
        omnipool.dola_pool.PoolApproval[-1],
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_portal.lending.LendingPortal[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        sui_project[SuiObject.from_type(
            pool(coin_type))][account_address][-1],
        int(amount),
        type_arguments=[coin_type]
    )


def portal_borrow_remote(pool_addr, amount, dst_chain=0, receiver=None):
    """
    public entry fun borrow_remote(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        core_state: &mut CoreState,
        dola_portal: &DolaPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver: vector<u8>,
        dst_chain: u16,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        assert dst_chain == 0
        receiver = account_address

    dola_portal.lending.borrow_remote(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        dola_portal.lending.LendingPortal[-1],
        wormhole.state.State[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        pool_addr,
        receiver,
        dst_chain,
        int(amount)
    )


def core_borrow(vaa, relay_fee=0):
    """
    public entry fun borrow(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = sui_project.pay_sui([0])
    zero_coin = result['objectChanges'][-1]['objectId']

    result = lending_core.wormhole_adapter.borrow(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        zero_coin,
        vaa,
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.borrow(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            zero_coin,
            vaa,
        )
    return gas, executed


def portal_repay(coin_type):
    """
    public entry fun repay<CoinType>(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_portal: &DolaPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    user_manager = load.user_manager_package()
    pool_manager = load.pool_manager_package()
    account_address = dola_portal.account.account_address

    dola_portal.lending.repay(
        lending_core.storage.Storage[-1],
        oracle.oracle.PriceOracle[-1],
        dola_portal.lending.LendingPortal[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        sui_project[SuiObject.from_type(pool(coin_type))]["Shared"][-1],
        [sui_project[SuiObject.from_type(
            coin(coin_type))][account_address][-1]],
        U64_MAX,
        type_arguments=[coin_type]
    )


def core_repay(vaa, relay_fee=0):
    """
    public entry fun repay(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = lending_core.wormhole_adapter.repay.simulate(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        vaa
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.repay(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            vaa
        )
    return gas, executed


def portal_liquidate(debt_coin_type, collateral_coin_type, dst_chain=0, receiver=None):
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
    dola_portal = load.dola_portal_package()
    omnipool = load.omnipool_package()
    wormhole = load.wormhole_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        receiver = account_address

    dola_portal.lending.liquidate(
        omnipool.wormhole_adapter_pool.PoolState[-1],
        wormhole.state.State[-1],
        receiver,
        dst_chain,
        [],
        0,
        sui_project[SuiObject.from_type(
            pool(debt_coin_type))][account_address][-1],
        [sui_project[SuiObject.from_type(
            coin(debt_coin_type))][account_address][-1]],
        U64_MAX,
        0,
        type_arguments=[debt_coin_type, collateral_coin_type]
    )
    return bridge_pool_read_vaa()[0]


def core_liquidate(vaa, relay_fee=0):
    """
    public entry fun liquidate(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = lending_core.wormhole_adapter.liquidate.simulate(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        vaa,
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.liquidate(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            vaa,
        )
    return gas, executed


def portal_binding(bind_address, dola_chain_id=0):
    """
    public entry fun binding(
        system_portal: &mut SystemPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        binded_address: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    user_manager = load.user_manager_package()

    dola_portal.system.binding(
        dola_portal.system.SystemPortal[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        dola_chain_id,
        list(bytes.fromhex(bind_address))
    )


def core_binding(vaa, relay_fee=0):
    """
    public entry fun bind_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        wormhole_adapter: &mut WormholeAdapter,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>
    )
    :return:
    """
    system_core = load.system_core_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    user_manager = load.user_manager_package()

    result = system_core.wormhole_adapter.bind_user_address.simulate(
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        system_core.wormhole_adapter.WormholeAdapter[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        system_core.storage.Storage[-1],
        vaa
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        system_core.wormhole_adapter.bind_user_address(
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            system_core.wormhole_adapter.WormholeAdapter[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            system_core.storage.Storage[-1],
            vaa
        )
    return gas, executed


def portal_unbinding(unbind_address, dola_chain_id=0):
    """
    public entry fun unbinding(
        system_portal: &mut SystemPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        unbinded_address: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    user_manager = load.user_manager_package()

    dola_portal.system.unbinding(
        dola_portal.system.SystemPortal[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        dola_chain_id,
        unbind_address
    )


def core_unbinding(vaa, relay_fee=0):
    """
    public entry fun unbind_user_address(
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        wormhole_adapter: &mut WormholeAdapter,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>
    )
    :return:
    """
    system_core = load.system_core_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    user_manager = load.user_manager_package()

    result = system_core.wormhole_adapter.unbind_user_address.simulate(
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        system_core.wormhole_adapter.WormholeAdapter[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        system_core.storage.Storage[-1],
        vaa
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        system_core.wormhole_adapter.unbind_user_address(
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            system_core.wormhole_adapter.WormholeAdapter[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            system_core.storage.Storage[-1],
            vaa
        )
    return gas, executed


def core_as_collateral(vaa, relay_fee=0):
    """
    public entry fun as_collateral(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>
    )
    :param relay_fee:
    :param vaa:
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = lending_core.wormhole_adapter.as_collateral.simulate(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        vaa
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.as_collateral(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            vaa
        )
    return gas, executed


def core_cancel_as_collateral(vaa, relay_fee=0):
    """
    public entry fun cancel_as_collateral(
        wormhole_adapter: &WormholeAdapter,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        clock: &Clock,
        vaa: vector<u8>
    )
    :return:
    """
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    oracle = load.oracle_package()

    result = lending_core.wormhole_adapter.cancel_as_collateral.simulate(
        lending_core.wormhole_adapter.WormholeAdapter[-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        user_manager.user_manager.UserManagerInfo[-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        oracle.oracle.PriceOracle[-1],
        lending_core.storage.Storage[-1],
        clock(),
        vaa
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        lending_core.wormhole_adapter.cancel_as_collateral(
            lending_core.wormhole_adapter.WormholeAdapter[-1],
            pool_manager.pool_manager.PoolManagerInfo[-1],
            user_manager.user_manager.UserManagerInfo[-1],
            wormhole.state.State[-1],
            wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
            oracle.oracle.PriceOracle[-1],
            lending_core.storage.Storage[-1],
            clock(),
            vaa
        )
    return gas, executed


def export_objects():
    # Package id
    dola_portal = load.dola_portal_package()
    external_interfaces = load.external_interfaces_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    lending_core = load.lending_core_package()
    system_core = load.system_core_package()
    test_coins = load.test_coins_package()
    print(f"dola_portal={dola_portal.package_id}")
    print(f"external_interfaces={external_interfaces.package_id}")
    print(f"wormhole_adapter_core={wormhole_adapter_core.package_id}")
    print(f"lending_core={lending_core.package_id}")
    print(f"system_core={system_core.package_id}")
    print(f"test_coins={test_coins.package_id}")

    # objects
    wormhole = load.wormhole_package()
    oracle = load.oracle_package()
    lending_core = load.lending_core_package()
    pool_manager = load.pool_manager_package()
    user_manager = load.user_manager_package()
    omnipool = load.omnipool_package()

    data = {
        "PoolApproval": omnipool.dola_pool.PoolApproval[-1],
        "PoolState": omnipool.wormhole_adapter_pool.PoolState[-1],
        "CoreState": wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        "WormholeState": wormhole.state.State[-1],
        "DolaPortal": dola_portal.lending.LendingPortal[-1],
        "PriceOracle": oracle.oracle.PriceOracle[-1],
        "Storage": lending_core.storage.Storage[-1],
        "Faucet": test_coins.faucet.Faucet[-1],
        "PoolManagerInfo": pool_manager.pool_manager.PoolManagerInfo[-1],
        "UserManagerInfo": user_manager.user_manager.UserManagerInfo[-1],
        "Clock": clock(),
    }
    coin_types = [btc(), usdt(), usdc(), "0x2::sui::SUI"]
    for k in coin_types:
        coin_key = k.split("::")[-1]
        data[coin_key] = k.replace("0x", "")
        dk = f'Pool<{k.split("::")[-1]}>'
        data[dk] = sui_project[SuiObject.from_type(pool(k))][-1]

    data['SUI'] = sui().removeprefix("0x")
    pprint(data)


def monitor_supply(coin):
    portal_supply(coin)
    # core_supply(vaa)


def monitor_withdraw(coin, amount=1):
    portal_withdraw_local(coin, amount * 1e7)
    # to_pool_vaa = core_withdraw(to_core_vaa)
    # pool_withdraw(to_pool_vaa, coin)


def monitor_borrow(coin, amount=1):
    portal_borrow_local(coin, amount * 1e7)
    # to_pool_vaa = core_borrow(to_core_vaa)
    # pool_withdraw(to_pool_vaa, coin)


def monitor_repay(coin):
    portal_repay(coin)
    # core_repay(vaa)


def monitor_liquidate():
    vaa = portal_liquidate(usdt(), btc())
    # core_repay(vaa)


def check_pool_info():
    pool_manager = load.pool_manager_package()
    pool_manager_info = pool_manager.get_object_with_super_detail(
        pool_manager.pool_manager.PoolManagerInfo[-1])

    print("\n --- app liquidity info ---")
    pprint(pool_manager_info)


def check_app_storage():
    lending_core = load.lending_core_package()
    storage = lending_core.get_object_with_super_detail(lending_core.storage.Storage[-1])
    print("\n --- app storage info ---")
    pprint(storage)


def check_user_manager():
    user_manager = load.user_manager_package()
    storage = user_manager.get_object_with_super_detail(
        user_manager.user_manager.UserManagerInfo[-1])
    print("\n --- user manager info ---")
    pprint(storage)


if __name__ == "__main__":
    portal_binding("29b710abd287961d02352a5e34ec5886c63aa5df87a209b2acbdd7c9282e6566")
    # claim_test_coin(usdt())
    # monitor_supply(usdt())
    # portal_withdraw_remote(bytes(usdt().removeprefix("0x"), "ascii"), 1e7)
    # force_claim_test_coin(usdc(), 100000)
    # monitor_supply(usdc())
    # monitor_supply(sui())
    # monitor_borrow(usdt())
    # monitor_repay(usdt())
    # check_pool_info()
    # check_app_storage()
    # check_user_manager()
    # export_objects()
