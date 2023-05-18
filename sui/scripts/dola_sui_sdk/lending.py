from pathlib import Path
from pprint import pprint

import yaml
from sui_brownie import SuiObject

from dola_sui_sdk import load, init
from dola_sui_sdk.init import pool
from dola_sui_sdk.init import wbtc, usdt, usdc, sui, clock
from dola_sui_sdk.load import sui_project

U64_MAX = 18446744073709551615


def calculate_sui_gas(gas_used):
    return int(gas_used['computationCost']) + int(gas_used['storageCost']) - int(
        gas_used['storageRebate'])


def get_zero_coin():
    sui_coins = sui_project.get_account_sui()
    if len(sui_coins) == 1:
        result = sui_project.pay_sui([0])
        return result['objectChanges'][-1]['objectId']
    elif len(sui_coins) == 2 and 0 in [coin['balance'] for coin in sui_coins.values()]:
        return [coin_object for coin_object, coin in sui_coins.items() if coin['balance'] == 0][0]
    else:
        sui_project.pay_all_sui()
        result = sui_project.pay_sui([0])
        return result['objectChanges'][-1]['objectId']


def portal_as_collateral(pool_ids=None):
    """
    public entry fun as_collateral(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        dola_pool_ids: vector<u16>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    if pool_ids is None:
        pool_ids = []

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    dola_protocol.lending_portal.as_collateral(
        genesis,
        storage,
        oracle,
        init.clock(),
        pool_manager_info,
        user_manager_info,
        pool_ids
    )


def portal_cancel_as_collateral(pool_ids=None):
    """
    public entry fun cancel_as_collateral(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        dola_pool_ids: vector<u16>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    if pool_ids is None:
        pool_ids = []

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    dola_protocol.lending_portal.cancel_as_collateral(
        genesis,
        storage,
        oracle,
        init.clock(),
        pool_manager_info,
        user_manager_info,
        pool_ids
    )


def portal_supply(coin_type, amount):
    """
    public entry fun supply<CoinType>(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
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
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']

    result = sui_project.client.suix_getCoins(sui_project.account.account_address, coin_type, None, None)
    deposit_coins = [c["coinObjectId"] for c in result["data"]]

    dola_protocol.lending_portal.supply(
        genesis,
        storage,
        oracle,
        init.clock(),
        lending_portal,
        user_manager_info,
        pool_manager_info,
        init.pool_id(coin_type),
        deposit_coins,
        amount,
        type_arguments=[coin_type]
    )


def core_supply(vaa, relay_fee=0):
    """
    public entry fun supply(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :param relay_fee:
    :param vaa:
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    result = dola_protocol.lending_core_wormhole_adapter.supply.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock(),
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])

    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.supply(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
        )
    return gas, executed


def portal_withdraw_local(coin_type, amount):
    """
    public entry fun withdraw_local<CoinType>(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    dola_protocol.lending_portal.withdraw_local(
        genesis,
        storage,
        oracle,
        init.clock(),
        lending_portal,
        pool_manager_info,
        user_manager_info,
        init.pool_id(coin_type),
        amount,
        type_arguments=[coin_type]
    )


def portal_withdraw_remote(pool_addr, amount, relay_fee=0, dst_chain=0, receiver=None):
    """
    public entry fun withdraw_remote(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        core_state: &mut CoreState,
        lending_portal: &mut LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        bridge_fee_coins: vector<Coin<SUI>>,
        bridge_fee_amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    account_address = sui_project.account.account_address
    if receiver is None:
        assert dst_chain == 0
        receiver = account_address

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    core_state = sui_project.network_config['objects']['CoreState']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    gas_coin = get_zero_coin()

    dola_protocol.lending_portal.withdraw_remote(
        genesis,
        storage,
        oracle,
        init.clock(),
        core_state,
        lending_portal,
        wormhole_state,
        pool_manager_info,
        user_manager_info,
        pool_addr,
        receiver,
        dst_chain,
        amount,
        [gas_coin],
        0,
    )


def pool_withdraw(vaa, coin_type, relay_fee=0):
    """
    public entry fun receive_withdraw<CoinType>(
        genesis: &GovernanceGenesis,
        wormhole_state: &mut WormholeState,
        pool_state: &mut PoolState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :param coin_type:
    :param vaa:
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    pool_state = sui_project.network_config['objects']['PoolState']

    result = dola_protocol.wormhole_adapter_pool.receive_withdraw.simulate(
        genesis,
        wormhole_state,
        pool_state,
        init.pool_id(coin_type),
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock(),
        type_arguments=[coin_type]
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])

    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.wormhole_adapter_pool.receive_withdraw(
            genesis,
            wormhole_state,
            pool_state,
            init.pool_id(coin_type),
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
            type_arguments=[coin_type]
        )
    return gas, executed


def core_withdraw(vaa, relay_fee=0):
    """
    public entry fun withdraw(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    zero_coin = get_zero_coin()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    wormhole_message_fee = sui_project.network_config['objects']['WormholeMessageFee']

    gas_coin = get_zero_coin()

    result = dola_protocol.lending_core_wormhole_adapter.withdraw.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        gas_coin,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock()
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.withdraw(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            gas_coin,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
        )

    return gas, executed


def portal_borrow_local(coin_type, amount):
    """
    public entry fun borrow_local<CoinType>(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        lending_portal: &mut LendingPortal,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: &mut Pool<CoinType>,
        amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    clock = sui_project.network_config['objects']['Clock']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    gas_coin = get_zero_coin()

    dola_protocol.lending_portal.borrow_local(
        genesis,
        storage,
        oracle,
        clock,
        lending_portal,
        pool_manager_info,
        user_manager_info,
        init.pool_id(coin_type),
        amount,
        [gas_coin],
        0,
        type_arguments=[coin_type]
    )


def portal_borrow_remote(pool_addr, amount, dst_chain=0, receiver=None):
    """
    public entry fun borrow_remote(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        core_state: &mut CoreState,
        lending_portal: &mut LendingPortal,
        wormhole_state: &mut WormholeState,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        pool: vector<u8>,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        bridge_fee_coins: vector<Coin<SUI>>,
        bridge_fee_amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        assert dst_chain == 0
        receiver = account_address

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    clock = sui_project.network_config['objects']['Clock']
    core_state = sui_project.network_config['objects']['CoreState']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    gas_coin = get_zero_coin()

    dola_protocol.lending_portal.borrow_remote(
        genesis,
        storage,
        oracle,
        clock,
        core_state,
        lending_portal,
        wormhole_state,
        pool_manager_info,
        user_manager_info,
        pool_addr,
        receiver,
        dst_chain,
        amount,
        [gas_coin],
        0
    )


def core_borrow(vaa, relay_fee=0):
    """
    public entry fun borrow(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        wormhole_message_fee: Coin<SUI>,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    gas_coin = get_zero_coin()

    result = dola_protocol.lending_core_wormhole_adapter.borrow.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        gas_coin,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock,
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.borrow(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            gas_coin,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock,
        )
    return gas, executed


def portal_repay(coin_type, repay_amount):
    """
    public entry fun repay<CoinType>(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        lending_portal: &mut LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        pool: &mut Pool<CoinType>,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    clock = sui_project.network_config['objects']['Clock']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    pool = sui_project.network_config['objects']['Pool']

    result = sui_project.client.suix_getCoins(sui_project.account.account_address, coin_type, None, None)
    repay_coins = [c["coinObjectId"] for c in result["data"]]

    dola_protocol.lending_portal.repay(
        genesis,
        storage,
        oracle,
        clock,
        lending_portal,
        user_manager_info,
        pool_manager_info,
        pool,
        repay_coins,
        repay_amount,
        type_arguments=[coin_type]
    )


def core_repay(vaa, relay_fee=0):
    """
    public entry fun repay(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.lending_core_wormhole_adapter.repay.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock,
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.repay(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock,
        )
    return gas, executed


def portal_liquidate(debt_coin_type, deposit_amount, collateral_pool_address, collateral_chain_id, violator_id):
    """
    public entry fun liquidate<DebtCoinType>(
        genesis: &GovernanceGenesis,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        clock: &Clock,
        lending_portal: &mut LendingPortal,
        user_manager_info: &mut UserManagerInfo,
        pool_manager_info: &mut PoolManagerInfo,
        debt_pool: &mut Pool<DebtCoinType>,
        // liquidators repay debts to obtain collateral
        debt_coins: vector<Coin<DebtCoinType>>,
        debt_amount: u64,
        liquidate_chain_id: u16,
        liquidate_pool_address: vector<u8>,
        liquidate_user_id: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    storage = sui_project.network_config['objects']['LendingStorage']
    oracle = sui_project.network_config['objects']['PriceOracle']
    clock = sui_project.network_config['objects']['Clock']
    lending_portal = sui_project.network_config['objects']['LendingPortal']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']

    result = sui_project.client.suix_getCoins(sui_project.account.account_address, debt_coin_type, None, None)
    debt_coins = [c["coinObjectId"] for c in result["data"]]

    dola_portal.lending.liquidate(
        genesis,
        storage,
        oracle,
        clock,
        lending_portal,
        user_manager_info,
        pool_manager_info,
        init.pool_id(debt_coin_type),
        debt_coins,
        int(deposit_amount),
        int(collateral_chain_id),
        list(bytes.fromhex(collateral_pool_address.replace('0x', ''))),
        int(violator_id),
        type_arguments=[debt_coin_type]
    )


def core_liquidate(vaa, relay_fee=0):
    """
    public entry fun liquidate(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.lending_core_wormhole_adapter.liquidate.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock,
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.liquidate(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock,
        )
    return gas, executed


def portal_binding(bind_address, dola_chain_id=0):
    """
    public entry fun binding(
        genesis: &GovernanceGenesis,
        system_portal: &mut SystemPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        binded_address: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    system_portal = sui_project.network_config['objects']['SystemPortal']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    dola_protocol.system_portal.binding(
        genesis,
        system_portal,
        user_manager_info,
        int(dola_chain_id),
        list(bytes.fromhex(bind_address))
    )


def core_binding(vaa, relay_fee=0):
    """
    public entry fun bind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.system_core_wormhole_adapter.bind_user_address.simulate(
        genesis,
        user_manager_info,
        wormhole_state,
        core_state,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.system_core_wormhole_adapter.bind_user_address(
            genesis,
            user_manager_info,
            wormhole_state,
            core_state,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock
        )
    return gas, executed


def portal_unbinding(unbind_address, dola_chain_id=0):
    """
    public entry fun unbinding(
        genesis: &GovernanceGenesis,
        system_portal: &mut SystemPortal,
        user_manager_info: &mut UserManagerInfo,
        dola_chain_id: u16,
        unbinded_address: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    system_portal = sui_project.network_config['objects']['SystemPortal']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']

    dola_protocol.system_portal.unbinding(
        genesis,
        system_portal,
        user_manager_info,
        int(dola_chain_id),
        list(bytes.fromhex(unbind_address.replace('0x', '')))
    )


def core_unbinding(vaa, relay_fee=0):
    """
    public entry fun unbind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        storage: &Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.system_core_wormhole_adapter.unbind_user_address.simulate(
        genesis,
        user_manager_info,
        wormhole_state,
        core_state,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.system_core_wormhole_adapter.unbind_user_address(
            genesis,
            user_manager_info,
            wormhole_state,
            core_state,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock
        )
    return gas, executed


def core_as_collateral(vaa, relay_fee=0):
    """
    public entry fun as_collateral(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :param relay_fee:
    :param vaa:
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.lending_core_wormhole_adapter.as_collateral.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.as_collateral(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock
        )
    return gas, executed


def core_cancel_as_collateral(vaa, relay_fee=0):
    """
    public entry fun cancel_as_collateral(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        vaa: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    clock = sui_project.network_config['objects']['Clock']

    result = dola_protocol.lending_core_wormhole_adapter.cancel_as_collateral.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        clock
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas:
        executed = True
        dola_protocol.lending_core_wormhole_adapter.cancel_as_collateral(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            clock
        )
    return gas, executed


def export_objects():
    # Package id
    dola_protocol = load.dola_protocol_package()
    external_interfaces = load.external_interfaces_package()
    test_coins = load.test_coins_package()
    print(f"dola_protocol={dola_protocol.package_id}")
    print(f"external_interfaces={external_interfaces.package_id}")
    print(f"test_coins={test_coins.package_id}")

    data = {
        "GovernanceGenesis": dola_protocol.genesis.GovernanceGenesis[-1],
        "GovernanceInfo": dola_protocol.governance_v1.GovernanceInfo[-1],
        "PoolState": dola_protocol.wormhole_adapter_pool.PoolState[-1],
        "CoreState": dola_protocol.wormhole_adapter_core.CoreState[-1],
        "WormholeState": sui_project.network_config['objects']['WormholeState'],
        "LendingPortal": dola_protocol.lending_portal.LendingPortal[-1],
        "SystemPortal": dola_protocol.system_portal.SystemPortal[-1],
        "PriceOracle": dola_protocol.oracle.PriceOracle[-1],
        "LendingStorage": dola_protocol.lending_core_storage.Storage[-1],
        "Faucet": test_coins.faucet.Faucet[-1],
        "PoolManagerInfo": dola_protocol.pool_manager.PoolManagerInfo[-1],
        "UserManagerInfo": dola_protocol.user_manager.UserManagerInfo[-1],
        "Clock": clock(),
    }

    coin_types = [wbtc(), usdt(), usdc(), "0x2::sui::SUI"]
    for k in coin_types:
        coin_key = k.split("::")[-1]
        data[coin_key] = k.replace("0x", "")
        dk = f'Pool<{k.split("::")[-1]}>'
        data[dk] = sui_project[SuiObject.from_type(pool(k))][-1]

    data['SUI'] = sui().removeprefix("0x")

    pprint(data)

    path = Path(__file__).parent.parent.parent.joinpath("brownie-config.yaml")
    with open(path, "r") as f:
        config = yaml.safe_load(f)

    current_network = sui_project.network
    for key in data:
        config["networks"][current_network]["objects"][key] = data[key]

    with open(path, "w") as f:
        yaml.safe_dump(config, f)


if __name__ == "__main__":
    # portal_binding("a65b84b73c857082b680a148b7b25327306d93cc7862bae0edfa7628b0342392")
    init.claim_test_coin(usdt())
    portal_supply(usdt(), int(1e8))

    # oracle.feed_token_price_by_pyth('USDT/USD')
    # portal_withdraw_local(usdt(), int(1e8))

    # export_objects()
