from pathlib import Path
from pprint import pprint

import yaml
from dola_sui_sdk import load, init
from dola_sui_sdk.init import pool
from dola_sui_sdk.init import wbtc, usdt, usdc, sui, clock
from dola_sui_sdk.load import sui_project
from dola_sui_sdk.oracle import get_price_info_object, get_feed_vaa, build_feed_transaction_block
from sui_brownie import SuiObject, Argument, U16, NestedResult

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
        return 'USDT/USD'
    elif dola_pool_id == 3:
        return 'ETH/USD'
    elif dola_pool_id == 4:
        return 'MATIC/USD'
    elif dola_pool_id == 5:
        return 'SUI/USD'
    else:
        raise ValueError('dola_pool_id must be 0, 1, 2, 3, 4 or 5')


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


def get_owned_zero_coin():
    sui_coins = sui_project.get_account_sui()
    return [coin_object for coin_object, coin in sui_coins.items() if coin['balance'] == '0'][0]


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
    pyth = load.pyth_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    pyth_state = sui_project.network_config['objects']['PythState']

    asset_ids = get_withdraw_user_asset_ids_from_vaa(vaa)

    result = pyth.state.get_base_update_fee.inspect(pyth_state)
    pyth_fee_amount = int(parse_u64(result['results'][0]['returnValues'][0][0]) / 5 + 1)
    symbols = [dola_pool_id_to_symbol(asset_id) for asset_id in asset_ids]

    sui_project.pay_all_sui()
    fee_amounts = [pyth_fee_amount] * len(symbols)
    result = sui_project.pay_sui(fee_amounts + [0])
    fee_coins = [coin['reference']['objectId'] for coin in result['effects']['created']]
    zero_coin = get_owned_zero_coin()
    fee_coins.remove(zero_coin)

    basic_params = [
        pool_manager_info,  # 0
        user_manager_info,  # 1
        core_state,  # 2
        storage,  # 3
        zero_coin,  # 4
        list(bytes.fromhex(vaa.replace('0x', ''))),  # 5
        genesis,  # 6
        wormhole_state,  # 7
        pyth_state,  # 8
        oracle,  # 9
        init.clock(),  # 10
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

    withdraw_transaction_block = [[
        dola_protocol.lending_core_wormhole_adapter.withdraw,
        [
            Argument("Input", U16(6)),
            Argument("Input", U16(0)),
            Argument("Input", U16(1)),
            Argument("Input", U16(7)),
            Argument("Input", U16(2)),
            Argument("Input", U16(9)),
            Argument("Input", U16(3)),
            Argument("Input", U16(4)),
            Argument("Input", U16(5)),
            Argument("Input", U16(10)),
        ],
        []
    ]]

    result = sui_project.batch_transaction_simulate(
        actual_params=basic_params + feed_params,
        transactions=feed_transaction_blocks + withdraw_transaction_block,
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas and status == 'success':
        executed = True
        sui_project.batch_transaction(
            actual_params=basic_params + feed_params,
            transactions=feed_transaction_blocks + withdraw_transaction_block,
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
    account_address = dola_protocol.account.account_address
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
    pyth = load.pyth_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']
    pyth_state = sui_project.network_config['objects']['PythState']

    asset_ids = get_withdraw_user_asset_ids_from_vaa(vaa)

    result = pyth.state.get_base_update_fee.inspect(pyth_state)
    pyth_fee_amount = int(parse_u64(result['results'][0]['returnValues'][0][0]) / 5 + 1)
    symbols = [dola_pool_id_to_symbol(asset_id) for asset_id in asset_ids]

    sui_project.pay_all_sui()
    fee_amounts = [pyth_fee_amount] * len(symbols)
    result = sui_project.pay_sui(fee_amounts + [0])
    fee_coins = [coin['reference']['objectId'] for coin in result['effects']['created']]
    zero_coin = get_owned_zero_coin()
    fee_coins.remove(zero_coin)

    basic_params = [
        pool_manager_info,  # 0
        user_manager_info,  # 1
        core_state,  # 2
        storage,  # 3
        zero_coin,  # 4
        list(bytes.fromhex(vaa.replace('0x', ''))),  # 5
        genesis,  # 6
        wormhole_state,  # 7
        pyth_state,  # 8
        oracle,  # 9
        init.clock(),  # 10
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

    withdraw_transaction_block = [[
        dola_protocol.lending_core_wormhole_adapter.borrow,
        [
            Argument("Input", U16(6)),
            Argument("Input", U16(0)),
            Argument("Input", U16(1)),
            Argument("Input", U16(7)),
            Argument("Input", U16(2)),
            Argument("Input", U16(9)),
            Argument("Input", U16(3)),
            Argument("Input", U16(4)),
            Argument("Input", U16(5)),
            Argument("Input", U16(10)),
        ],
        []
    ]]

    result = sui_project.batch_transaction_simulate(
        actual_params=basic_params + feed_params,
        transactions=feed_transaction_blocks + withdraw_transaction_block,
    )

    status = result['results']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if relay_fee > gas and status == 'success':
        executed = True
        sui_project.batch_transaction(
            actual_params=basic_params + feed_params,
            transactions=feed_transaction_blocks + withdraw_transaction_block,
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

    dola_protocol.lending.liquidate(
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


def parse_u16(vec):
    return vec[0] + (vec[1] << 8)


def parse_u64(data: list):
    output = 0
    for i in range(8):
        output = (output << 8) + int(data[7 - i])
    return output


def convert_vec_u16_to_list(vec):
    length = vec[0]
    return [parse_u16(vec[1 + i * 2: 3 + i * 2]) for i in range(length)]


def get_withdraw_user_asset_ids_from_vaa(vaa):
    dola_protocol = load.dola_protocol_package()
    wormhole = load.wormhole_package()

    wormhole_state = sui_project.network_config['objects']['WormholeState']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    lending_core_storage = sui_project.network_config['objects']['LendingStorage']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']

    result = sui_project.batch_transaction_inspect(
        actual_params=[
            wormhole_state,
            list(bytes.fromhex(vaa.replace('0x', ''))),
            init.clock(),
            user_manager_info,
            lending_core_storage,
            pool_manager_info
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
                wormhole.vaa.payload,
                [
                    Argument("Result", U16(0)),
                ],
                []
            ],
            # 2. decode_send_message_payload
            [
                dola_protocol.pool_codec.decode_send_message_payload,
                [
                    Argument("Result", U16(1)),
                ],
                []
            ],
            # 3. get dola_user_id
            [
                dola_protocol.user_manager.get_dola_user_id,
                [
                    Argument("Input", U16(3)),
                    Argument("NestedResult", NestedResult(U16(2), U16(0))),
                ],
                []
            ],
            # 4. get user collateral
            [
                dola_protocol.lending_core_storage.get_user_collaterals,
                [
                    Argument("Input", U16(4)),
                    Argument("NestedResult", NestedResult(U16(3), U16(0))),
                ],
                []
            ],
            # 5. get user loans
            [
                dola_protocol.lending_core_storage.get_user_loans,
                [
                    Argument("Input", U16(4)),
                    Argument("NestedResult", NestedResult(U16(3), U16(0))),
                ],
                []
            ],
            # 6. decode_withdraw_payload
            [
                dola_protocol.lending_codec.decode_withdraw_payload,
                [
                    Argument("NestedResult", NestedResult(U16(2), U16(3))),
                ],
                []
            ],
            # 7. get withdraw pool id
            [
                dola_protocol.pool_manager.get_id_by_pool,
                [
                    Argument("Input", U16(5)),
                    Argument("NestedResult", NestedResult(U16(6), U16(3))),
                ],
                []
            ]
        ]
    )
    collateral_ids = convert_vec_u16_to_list(result["results"][4]["returnValues"][0][0])
    loan_ids = convert_vec_u16_to_list(result["results"][5]["returnValues"][0][0])
    withdraw_pool_id = [parse_u16(result["results"][7]["returnValues"][0][0])]
    return list(set(collateral_ids + loan_ids + withdraw_pool_id))


def get_violator_user_asset_ids_from_vaa(vaa):
    pass


if __name__ == "__main__":
    # portal_binding("a65b84b73c857082b680a148b7b25327306d93cc7862bae0edfa7628b0342392")
    # init.claim_test_coin(usdt())
    # portal_supply(usdt(), int(1e8))

    # oracle.feed_token_price_by_pyth('USDT/USD')
    # portal_withdraw_local(usdt(), int(1e8))

    export_objects()
