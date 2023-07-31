from pathlib import Path
from pprint import pprint

import ccxt
import requests
import yaml
from sui_brownie import SuiObject, Argument, U16

from dola_sui_sdk import load, init
from dola_sui_sdk.init import clock
from dola_sui_sdk.init import pool
from dola_sui_sdk.load import sui_project
from dola_sui_sdk.oracle import get_price_info_object, get_feed_vaa, build_feed_transaction_block

U64_MAX = 18446744073709551615


def calculate_sui_gas(gas_used):
    return int(gas_used['computationCost']) + int(gas_used['storageCost']) - int(
        gas_used['storageRebate'])


def dola_pool_id_to_symbol(dola_pool_id):
    if dola_pool_id == 0:
        return 'BTC/USD'
    elif dola_pool_id == 1:
        return 'USDT/USD'
    elif dola_pool_id == 2:
        return 'USDC/USD'
    elif dola_pool_id == 3:
        return 'SUI/USD'
    elif dola_pool_id == 4:
        return 'ETH/USD'
    elif dola_pool_id == 5:
        return 'MATIC/USD'
    elif dola_pool_id == 6:
        return 'ARB/USD'
    elif dola_pool_id == 7:
        return 'OP/USD'
    else:
        raise ValueError('dola_pool_id must be 0, 1, 2, 3, 4 or 5')


def feed_multi_token_price_with_fee(asset_ids, relay_fee=0):
    dola_protocol = load.dola_protocol_package()
    kucoin = ccxt.kucoin()
    kucoin.load_markets()

    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    pyth_state = sui_project.network_config['objects']['PythState']
    pyth_fee_amount = 0

    feed_gas = 0
    for pool_id in asset_ids:
        symbol = dola_pool_id_to_symbol(pool_id)

        vaa = get_feed_vaa(symbol)
        result = sui_project.batch_transaction_inspect(
            actual_params=[
                governance_genesis,
                wormhole_state,
                pyth_state,
                get_price_info_object(symbol),
                price_oracle,
                pool_id,
                list(bytes.fromhex(vaa.replace("0x", ""))),
                init.clock(),
                pyth_fee_amount
            ],
            transactions=[
                [
                    dola_protocol.oracle.feed_token_price_by_pyth,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
                    ],
                    []
                ],
                [
                    dola_protocol.oracle.get_token_price,
                    [
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                    ],
                    []
                ]
            ]
        )

        decimal = int(result['results'][2]['returnValues'][1][0][0])

        pyth_price = parse_u256(result['results'][2]['returnValues'][0][0]) / (10 ** decimal)
        if symbol in ['USDT/USD', 'USDC/USD']:
            kucoin_price = 1
        else:
            kucoin_price = kucoin.fetch_ticker(f"{symbol}T")['close']

        if pyth_price > kucoin_price:
            bias = 1 - kucoin_price / pyth_price
        else:
            bias = 1 - pyth_price / kucoin_price

        # todo: use this for mainnet
        # if bias > 0.01:
        #     raise ValueError("The oracle price difference is too large!")

        gas = calculate_sui_gas(result['effects']['gasUsed'])
        feed_gas += gas
        if relay_fee > int(0.9 * gas):
            sui_project.batch_transaction(
                actual_params=[
                    governance_genesis,
                    wormhole_state,
                    pyth_state,
                    get_price_info_object(symbol),
                    price_oracle,
                    pool_id,
                    list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
                    init.clock(),
                    pyth_fee_amount
                ],
                transactions=[
                    [
                        dola_protocol.oracle.feed_token_price_by_pyth,
                        [
                            Argument("Input", U16(0)),
                            Argument("Input", U16(1)),
                            Argument("Input", U16(2)),
                            Argument("Input", U16(3)),
                            Argument("Input", U16(4)),
                            Argument("Input", U16(5)),
                            Argument("Input", U16(6)),
                            Argument("Input", U16(7)),
                            Argument("Input", U16(8)),
                        ],
                        []
                    ]
                ]
            )
            relay_fee -= gas
    return relay_fee, feed_gas


def get_zero_coin():
    sui_coins = sui_project.get_account_sui()
    if len(sui_coins) == 1:
        result = sui_project.pay_sui([0])
        return result['effects']['created'][0]['reference']['objectId']
    elif len(sui_coins) == 2 and 0 in [coin['balance'] for coin in sui_coins.values()]:
        return [coin_object for coin_object, coin in sui_coins.items() if coin['balance'] == "0"][0]
    else:
        sui_project.pay_all_sui()
        result = sui_project.pay_sui([0])
        return result['effects']['created'][0]['reference']['objectId']


def get_amount_coins_if_exist(amounts: [int]):
    sui_coins = sui_project.get_account_sui()
    balances = [int(coin['balance']) for coin in sui_coins.values()]
    coins = [coin_object for coin_object, coin in sui_coins.items() if int(coin['balance']) in amounts]
    for amount in amounts:
        if amount not in balances:
            if sui_coins.__len__() > 1:
                sui_project.pay_all_sui()
            result = sui_project.pay_sui(amounts)
            return [coin['reference']['objectId'] for coin in result['effects']['created']]

    return coins


def get_owned_zero_coin():
    sui_coins = sui_project.get_account_sui()
    return [coin_object for coin_object, coin in sui_coins.items() if coin['balance'] == '0'][0]


def portal_as_collateral(pool_ids=None, bridge_fee=0):
    """
    entry fun as_collateral(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_pool_ids: vector<u16>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    if pool_ids is None:
        pool_ids = []

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([bridge_fee])

    dola_protocol.lending_portal_v2.as_collateral(
        genesis,
        pool_state,
        wormhole_state,
        coins[0],
        pool_ids,
        init.clock(),
    )


def portal_cancel_as_collateral(pool_ids=None, bridge_fee=0):
    """
    entry fun cancel_as_collateral(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_pool_ids: vector<u16>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    if pool_ids is None:
        pool_ids = []

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([bridge_fee])

    dola_protocol.lending_portal_v2.cancel_as_collateral(
        genesis,
        pool_state,
        wormhole_state,
        pool_ids,
        coins[0],
        init.clock(),
    )


def portal_supply(coin_type, amount, bridge_fee=0):
    """
    entry fun supply<CoinType>(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        pool: &mut Pool<CoinType>,
        deposit_coins: vector<Coin<CoinType>>,
        deposit_amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :param amount:
    :param coin_type:
    :return: payload
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([amount, bridge_fee])

    dola_protocol.lending_portal_v2.supply(
        genesis,
        pool_state,
        wormhole_state,
        init.pool_id(coin_type),
        [coins[0]],
        amount,
        coins[1],
        init.clock(),
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
    status = result['effects']['status']['status']

    executed = False
    if relay_fee > int(0.9 * gas):
        executed = True
        result = dola_protocol.lending_core_wormhole_adapter.supply(
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
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def portal_withdraw(pool_addr, amount, dst_chain_id=0, receiver=None, bridge_fee=0):
    """
    entry fun withdraw(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain_id: u16,
        pool: vector<u8>,
        receiver: vector<u8>,
        amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    account_address = sui_project.account.account_address
    if receiver is None:
        assert dst_chain_id == 0
        receiver = account_address

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([bridge_fee])

    dola_protocol.lending_portal_v2.withdraw(
        genesis,
        pool_state,
        wormhole_state,
        dst_chain_id,
        list(bytes(pool_addr.replace('0x', ''), 'ascii')),
        list(bytes.fromhex(receiver.replace('0x', ''))),
        amount,
        coins[0],
        init.clock(),
    )


def pool_withdraw(vaa, coin_type):
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
    :param relay_fee:
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
    status = result['effects']['status']['status']

    if status != 'success':
        return gas, False, result['effects']['status']['error'], ""

    result = dola_protocol.wormhole_adapter_pool.receive_withdraw(
        genesis,
        wormhole_state,
        pool_state,
        init.pool_id(coin_type),
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock(),
        type_arguments=[coin_type]
    )

    return gas, True, status, result['effects']['transactionDigest']


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

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    asset_ids = get_feed_tokens_for_relayer(vaa, is_withdraw=True)
    feed_nums = len(asset_ids)

    left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee)

    result = sui_project.batch_transaction_simulate(
        actual_params=[
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            0,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
        ],
        transactions=[
            [
                dola_protocol.lending_core_wormhole_adapter.withdraw,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    Argument("Input", U16(5)),
                    Argument("Input", U16(6)),
                    Argument("Input", U16(7)),
                    Argument("Input", U16(8)),
                    Argument("Input", U16(9)),
                ],
                []
            ]
        ]
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if left_relay_fee > int(0.9 * gas) and status == 'success':
        executed = True
        result = sui_project.batch_transaction(
            actual_params=[
                genesis,
                pool_manager_info,
                user_manager_info,
                wormhole_state,
                core_state,
                oracle,
                storage,
                0,
                list(bytes.fromhex(vaa.replace('0x', ''))),
                init.clock(),
            ],
            transactions=[
                [
                    dola_protocol.lending_core_wormhole_adapter.withdraw,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
                        Argument("Input", U16(9)),
                    ],
                    []
                ]
            ]
        )
        return gas + feed_gas, executed, status, feed_nums, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas + feed_gas, executed, result['effects']['status']['error'], feed_nums, ""
    else:
        return gas + feed_gas, executed, status, feed_nums, ""


def portal_borrow(pool_addr, amount, dst_chain_id=0, receiver=None, bridge_fee=0):
    """
    entry fun borrow(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain_id: u16,
        pool: vector<u8>,
        receiver: vector<u8>,
        amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    account_address = sui_project.account.account_address
    if receiver is None:
        assert dst_chain_id == 0
        receiver = account_address

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([bridge_fee])

    dola_protocol.lending_portal_v2.borrow(
        genesis,
        pool_state,
        wormhole_state,
        dst_chain_id,
        pool_addr,
        receiver,
        amount,
        coins[0],
        init.clock(),
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

    asset_ids = get_feed_tokens_for_relayer(vaa, is_withdraw=True)
    feed_nums = len(asset_ids)

    left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee)

    result = sui_project.batch_transaction_simulate(
        actual_params=[
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            0,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
        ],
        transactions=[
            [
                dola_protocol.lending_core_wormhole_adapter.borrow,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    Argument("Input", U16(5)),
                    Argument("Input", U16(6)),
                    Argument("Input", U16(7)),
                    Argument("Input", U16(8)),
                    Argument("Input", U16(9)),
                ],
                []
            ]
        ]
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if left_relay_fee > int(0.9 * gas) and status == 'success':
        executed = True
        result = sui_project.batch_transaction(
            actual_params=[
                genesis,
                pool_manager_info,
                user_manager_info,
                wormhole_state,
                core_state,
                oracle,
                storage,
                0,
                list(bytes.fromhex(vaa.replace('0x', ''))),
                init.clock(),
            ],
            transactions=[
                [
                    dola_protocol.lending_core_wormhole_adapter.borrow,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
                        Argument("Input", U16(9)),
                    ],
                    []
                ]
            ]
        )
        return gas + feed_gas, executed, status, feed_nums, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas + feed_gas, executed, result['effects']['status']['error'], feed_nums, ""
    else:
        return gas + feed_gas, executed, status, feed_nums, ""


def portal_repay(coin_type, repay_amount, bridge_fee=0):
    """
    public entry fun repay<CoinType>(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        pool: &mut Pool<CoinType>,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([repay_amount, bridge_fee])

    dola_protocol.lending_portal_v2.supply(
        genesis,
        pool_state,
        wormhole_state,
        init.pool_id(coin_type),
        [coins[0]],
        repay_amount,
        coins[1],
        init.clock(),
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
    status = result['effects']['status']['status']

    executed = False
    if relay_fee > int(0.9 * gas):
        executed = True
        result = dola_protocol.lending_core_wormhole_adapter.repay(
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
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def portal_liquidate(debt_coin_type, deposit_amount, collateral_pool_address, collateral_chain_id, violator_id,
                     bridge_fee=0):
    """
    entry fun liquidate<DebtCoinType>(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        // liquidators repay debts to obtain collateral
        debt_pool: &mut Pool<DebtCoinType>,
        debt_coins: vector<Coin<DebtCoinType>>,
        debt_amount: u64,
        liquidate_chain_id: u16,
        liquidate_pool_address: vector<u8>,
        liquidate_user_id: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([deposit_amount, bridge_fee])

    dola_protocol.lending.liquidate(
        genesis,
        pool_state,
        wormhole_state,
        init.pool_id(debt_coin_type),
        [coins[0]],
        int(deposit_amount),
        int(collateral_chain_id),
        list(bytes.fromhex(collateral_pool_address.replace('0x', ''))),
        int(violator_id),
        coins[1],
        init.clock(),
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
    pyth = load.pyth_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    pyth_state = sui_project.network_config['objects']['PythState']

    asset_ids = get_feed_tokens_for_relayer(vaa, is_liquidate=True)
    feed_nums = len(asset_ids)

    result = pyth.state.get_base_update_fee.inspect(pyth_state)
    pyth_fee_amount = int(parse_u64(result['results'][0]['returnValues'][0][0]) / 5 + 1)
    symbols = [dola_pool_id_to_symbol(asset_id) for asset_id in asset_ids]

    fee_amounts = [pyth_fee_amount] * len(symbols)
    fee_coins = get_amount_coins_if_exist(fee_amounts)

    basic_params = [
        pool_manager_info,  # 0
        user_manager_info,  # 1
        core_state,  # 2
        storage,  # 3
        list(bytes.fromhex(vaa.replace('0x', ''))),  # 4
        genesis,  # 5
        wormhole_state,  # 6
        pyth_state,  # 7
        oracle,  # 8
        init.clock(),  # 9
    ]

    feed_params = []
    feed_transaction_blocks = []

    for i, symbol in enumerate(symbols):
        feed_params += [
            get_price_info_object(symbol),
            asset_ids[i],
            list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
            fee_coins[i]
        ]
        feed_transaction_blocks.append(
            build_feed_transaction_block(dola_protocol, len(basic_params), len(feed_transaction_blocks)))

    liquidate_transaction_block = [[
        dola_protocol.lending_core_wormhole_adapter.liquidate,
        [
            Argument("Input", U16(5)),
            Argument("Input", U16(0)),
            Argument("Input", U16(1)),
            Argument("Input", U16(6)),
            Argument("Input", U16(2)),
            Argument("Input", U16(8)),
            Argument("Input", U16(3)),
            Argument("Input", U16(4)),
            Argument("Input", U16(9)),
        ],
        []
    ]]

    result = sui_project.batch_transaction_simulate(
        actual_params=basic_params + feed_params,
        transactions=feed_transaction_blocks + liquidate_transaction_block,
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > int(0.9 * gas) and status == 'success':
        executed = True
        result = sui_project.batch_transaction(
            actual_params=basic_params + feed_params,
            transactions=feed_transaction_blocks + liquidate_transaction_block,
        )

        return gas, executed, status, feed_nums, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], feed_nums, ""
    else:
        return gas, executed, status, feed_nums, ""


def portal_binding(bind_address, dola_chain_id=0, bridge_fee=0):
    """
    entry fun binding(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_chain_id: u16,
        binded_address: vector<u8>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([bridge_fee])

    dola_protocol.system_portal_v2.binding(
        genesis,
        pool_state,
        wormhole_state,
        int(dola_chain_id),
        list(bytes.fromhex(bind_address)),
        coins[0],
        init.clock()
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
    system_storage = sui_project.network_config['objects']['SystemStorage']

    result = dola_protocol.system_core_wormhole_adapter.bind_user_address.simulate(
        genesis,
        user_manager_info,
        wormhole_state,
        core_state,
        system_storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock()
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])

    status = result['effects']['status']['status']
    executed = False
    if relay_fee > int(0.9 * gas):
        executed = True
        result = dola_protocol.system_core_wormhole_adapter.bind_user_address(
            genesis,
            user_manager_info,
            wormhole_state,
            core_state,
            system_storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock()
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def portal_unbinding(unbind_address, dola_chain_id=0, bridge_fee=0):
    """
    entry fun unbinding(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_chain_id: u16,
        unbinded_address: vector<u8>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_state = sui_project.network_config['objects']['PoolState']
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    coins = get_amount_coins_if_exist([bridge_fee])

    dola_protocol.system_portal_v2.binding(
        genesis,
        pool_state,
        wormhole_state,
        int(dola_chain_id),
        list(bytes.fromhex(unbind_address)),
        coins[0],
        init.clock()
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
    system_storage = sui_project.network_config['objects']['SystemStorage']

    result = dola_protocol.system_core_wormhole_adapter.unbind_user_address.simulate(
        genesis,
        user_manager_info,
        wormhole_state,
        core_state,
        system_storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock()
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    status = result['effects']['status']['status']
    executed = False
    if relay_fee > int(0.9 * gas):
        executed = True
        result = dola_protocol.system_core_wormhole_adapter.unbind_user_address(
            genesis,
            user_manager_info,
            wormhole_state,
            core_state,
            system_storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock()
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


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
    status = result['effects']['status']['status']
    executed = False
    if relay_fee > int(0.9 * gas):
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
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


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

    asset_ids = get_feed_tokens_for_relayer(vaa, is_cancel_collateral=True)
    feed_nums = len(asset_ids)

    left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee)

    result = dola_protocol.lending_core_wormhole_adapter.cancel_as_collateral.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        init.clock()
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if left_relay_fee > int(0.9 * gas) and status == 'success':
        executed = True
        result = dola_protocol.lending_core_wormhole_adapter.cancel_as_collateral(
            genesis,
            pool_manager_info,
            user_manager_info,
            wormhole_state,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock()
        )

        return gas + feed_gas, executed, status, feed_nums, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas + feed_gas, executed, result['effects']['status']['error'], feed_nums, ""
    else:
        return gas + feed_gas, executed, status, feed_nums, ""


def export_objects():
    # Package id
    dola_protocol = load.dola_protocol_package()
    external_interfaces = load.external_interfaces_package()
    print(f"dola_protocol={dola_protocol.package_id}")
    print(f"external_interfaces={external_interfaces.package_id}")

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
        "SystemStorage": dola_protocol.system_core_storage.Storage[-1],
        "PoolManagerInfo": dola_protocol.pool_manager.PoolManagerInfo[-1],
        "UserManagerInfo": dola_protocol.user_manager.UserManagerInfo[-1],
        "Clock": clock(),
    }

    tokens = sui_project.network_config['tokens']

    for token in tokens:
        coin_type = tokens[token]['coin_type']
        data[token] = coin_type.replace("0x", "")
        dk = f'Pool<{token}>'
        data[dk] = sui_project[SuiObject.from_type(pool(coin_type))][-1]

    pprint(data)

    path = Path(__file__).parent.parent.parent.joinpath("brownie-config.yaml")
    with open(path, "r") as f:
        config = yaml.safe_load(f)

    current_network = sui_project.network
    for key in data:
        config["networks"][current_network]["objects"][key] = data[key]

    with open(path, "w") as f:
        yaml.safe_dump(config, f)


def parse_u16(vec):
    return vec[0] + (vec[1] << 8)


def parse_u64(data: list):
    output = 0
    for i in range(8):
        output = (output << 8) + int(data[7 - i])
    return output


def parse_u256(data: list):
    output = 0
    for i in range(32):
        output = (output << 8) + int(data[31 - i])
    return output


def convert_vec_u16_to_list(vec):
    length = vec[0]
    return [parse_u16(vec[1 + i * 2: 3 + i * 2]) for i in range(length)]


def parse_vaa(vaa):
    wormhole = load.wormhole_package()

    wormhole_state = sui_project.network_config['objects']['WormholeState']

    result = sui_project.batch_transaction_inspect(
        actual_params=[
            wormhole_state,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
        ],
        transactions=[
            # 0. parse_vaa
            [
                wormhole.vaa.parse_and_verify,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                ],
                []
            ],
            # 1. get_payload
            [
                wormhole.vaa.take_payload,
                [
                    Argument("Result", U16(0)),
                ],
                []
            ]
        ]
    )
    data = result['results'][1]['returnValues'][0][0]
    return ''.join([hex(i)[2:].zfill(2) for i in data])


def get_feed_tokens_for_relayer(vaa, is_withdraw=False, is_liquidate=False, is_cancel_collateral=False):
    """
    public fun get_feed_tokens_for_relayer(
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut State,
        storage: &mut Storage,
        price_oracle: &mut PriceOracle,
        vaa: vector<u8>,
        is_withdraw: bool,
        is_liquidate: bool,
        is_cancel_collateral: bool,
        clock: &Clock
    )
    :return:
    """
    external_interface = load.external_interfaces_package()

    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    result = external_interface.interfaces.get_feed_tokens_for_relayer.inspect(
        pool_manager_info,
        user_manager_info,
        wormhole_state,
        lending_storage,
        price_oracle,
        list(bytes.fromhex(vaa.replace('0x', ''))),
        is_withdraw,
        is_liquidate,
        is_cancel_collateral,
        init.clock()
    )
    if 'results' not in result:
        return []

    return convert_vec_u16_to_list(result['results'][0]['returnValues'][0][0])


def get_wormhole_fee():
    wormhole = load.wormhole_package()

    wormhole_state = sui_project.network_config['objects']['WormholeState']

    result = wormhole.state.message_fee.inspect(
        wormhole_state
    )
    return parse_u64(result['results'][0]['returnValues'][0][0])


def get_unrelay_txs(src_chian_id, call_name, limit=0):
    base_url = 'https://lending-relay-fee.omnibtc.finance'
    url = f'{base_url}/unrelay_txs/{src_chian_id}/{call_name}/{limit}'

    response = requests.get(url)
    return response.json()['result']


def get_sui_wormhole_payload(tx_hash):
    events = sui_project.client.sui_getEvents(tx_hash)
    wormhole = sui_project.network_config['packages']['wormhole']
    for event in events:
        if event['type'] == f'{wormhole}::publish_message::WormholeMessage':
            data = event['parsedJson']['payload']
            return ''.join([hex(i)[2:].zfill(2) for i in data])

    return ""


if __name__ == "__main__":
    # portal_binding("a65b84b73c857082b680a148b7b25327306d93cc7862bae0edfa7628b0342392")
    # init.claim_test_coin(usdt())
    # sui_project.pay_all_sui()
    # portal_supply(init.sui()['coin_type'], int(1e8), bridge_fee=7626000)
    portal_withdraw(init.sui()['coin_type'], int(1e8), bridge_fee=14813999)

    # export_objects()
