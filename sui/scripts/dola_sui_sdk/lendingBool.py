from sui_brownie import Argument, U16, NestedResult

import config
from dola_sui_sdk import load, init
from dola_sui_sdk.exchange import ExchangeManager
from dola_sui_sdk.load import sui_project
from dola_sui_sdk.oracle import get_feed_vaa

U64_MAX = 18446744073709551615

exchange_manager = ExchangeManager()

# copy from LibBoolAdapterVerify.sol
SERVER_OPCODE_SYSTEM_BINDING = 0
SERVER_OPCODE_SYSTEM_UNBINDING = 1
SERVER_OPCODE_LENDING_SUPPLY = 2
SERVER_OPCODE_LENDING_WITHDRAW = 3
SERVER_OPCODE_LENDING_BORROW = 4
SERVER_OPCODE_LENDING_REPAY = 5
SERVER_OPCODE_LENDING_LIQUIDATE = 6
SERVER_OPCODE_LENDING_COLLATERAL = 7
SERVER_OPCODE_LENDING_CANCEL_COLLATERAL = 8


def dispatch(message_raw: str, signature: str):
    msg_bytes = list(bytes.fromhex(message_raw.replace('0x', '')))
    opcode = msg_bytes[-1]

    if SERVER_OPCODE_SYSTEM_BINDING == opcode:
        core_binding(message_raw, signature)
    elif SERVER_OPCODE_SYSTEM_UNBINDING == opcode:
        core_unbinding(message_raw, signature)
    elif SERVER_OPCODE_LENDING_SUPPLY == opcode:
        core_supply(message_raw, signature)
    elif SERVER_OPCODE_LENDING_WITHDRAW == opcode:
        core_withdraw(message_raw, signature)
    elif SERVER_OPCODE_LENDING_BORROW == opcode:
        core_borrow(message_raw, signature)
    elif SERVER_OPCODE_LENDING_REPAY == opcode:
        core_repay(message_raw, signature)
    elif SERVER_OPCODE_LENDING_LIQUIDATE == opcode:
        core_liquidate(message_raw, signature)
    elif SERVER_OPCODE_LENDING_COLLATERAL == opcode:
        core_as_collateral(message_raw, signature)
    elif SERVER_OPCODE_LENDING_CANCEL_COLLATERAL == opcode:
        core_cancel_as_collateral(message_raw, signature)
    else:
        print(f"lendingBool dispatch: unexpect opcode={opcode}")
        raise ValueError


def dola_pool_id_to_symbol(pool_id):
    return config.DOLA_POOL_ID_TO_SYMBOL[pool_id]


def calculate_sui_gas(gas_used):
    return int(gas_used['computationCost']) + int(gas_used['storageCost']) - int(
        gas_used['storageRebate'])


def feed_multi_token_price_with_fee(asset_ids, relay_fee=0, fee_rate=0.8):
    dola_protocol = load.dola_protocol_package()

    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    price_oracle = sui_project.network_config['objects']['PriceOracle']
    pyth_state = sui_project.network_config['objects']['PythState']
    pyth_fee_amount = 1

    feed_gas = 0

    symbols = [config.DOLA_POOL_ID_TO_SYMBOL[pool_id] for pool_id in asset_ids]
    price_info_objects = [config.DOLA_POOL_ID_TO_PRICE_INFO_OBJECT[pool_id] for pool_id in asset_ids]
    vaas = [get_feed_vaa(symbol) for symbol in symbols]
    for (pool_id, symbol, price_info_object) in zip(asset_ids, symbols, price_info_objects):
        vaa = get_feed_vaa(symbol)
        result = sui_project.batch_transaction_inspect(
            actual_params=[
                governance_genesis,
                wormhole_state,
                pyth_state,
                price_info_object,
                price_oracle,
                pool_id,
                list(bytes.fromhex(vaa.replace("0x", ""))),
                init.clock(),
                pyth_fee_amount
            ],
            transactions=[
                [
                    dola_protocol.oracle.feed_token_price_by_pyth_v2,
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

        if f"{symbol}T" in config.EXCHANGE_SYMBOLS:
            exchange_price = exchange_manager.fetch_fastest_ticker(f"{symbol}T")['close']
        else:
            exchange_price = 1

        if pyth_price > exchange_price:
            deviation = 1 - exchange_price / pyth_price
        else:
            deviation = 1 - pyth_price / exchange_price

        deviation_threshold = config.SYMBOL_TO_DEVIATION[symbol]
        if deviation > deviation_threshold:
            print(f"The oracle price difference is too large! {symbol} deviation {deviation}!")
            # raise ValueError(f"The oracle price difference is too large! {symbol} deviation {deviation}!")

        gas = calculate_sui_gas(result['effects']['gasUsed'])
        feed_gas += gas

    if relay_fee >= int(fee_rate * feed_gas):
        relay_fee -= int(fee_rate * feed_gas)
        for (pool_id, vaa, symbol, price_info_object) in zip(asset_ids, vaas, symbols, price_info_objects):
            sui_project.batch_transaction(
                actual_params=[
                    governance_genesis,
                    wormhole_state,
                    pyth_state,
                    price_info_object,
                    price_oracle,
                    pool_id,
                    list(bytes.fromhex(vaa.replace("0x", ""))),
                    init.clock(),
                    pyth_fee_amount
                ],
                transactions=[
                    [
                        dola_protocol.oracle.feed_token_price_by_pyth_v2,
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
    amounts = [int(amount) for amount in amounts]
    sui_project.pay_sui(amounts)
    sui_coins = sui_project.get_account_sui()
    coin_objects = list(sui_coins.keys())
    balances = [int(sui_coins[coin_object]["balance"]) for coin_object in coin_objects]
    coins = []
    for amount in amounts:
        index = balances.index(amount)
        coins.append(coin_objects[index])
        del balances[index]
        del coin_objects[index]

    return coins


def get_owned_zero_coin():
    sui_coins = sui_project.get_account_sui()
    return [coin_object for coin_object, coin in sui_coins.items() if coin['balance'] == '0'][0]


def get_feed_tokens_for_relayer_bool(message_raw):
    """
    public fun get_feed_tokens_for_relayer_bool(
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        storage: &mut Storage,
        price_oracle: &mut PriceOracle,
        message_raw: vector<u8>,
        clock: &Clock
    )
    :return:
    """
    external_interface = load.external_interfaces_package()

    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']
    price_oracle = sui_project.network_config['objects']['PriceOracle']

    result = external_interface.interfaces.get_feed_tokens_for_relayer_bool.inspect(
        pool_manager_info,
        user_manager_info,
        lending_storage,
        price_oracle,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        init.clock()
    )

    if 'results' not in result:
        return []

    feed_token_ids = convert_vec_u16_to_list(result['results'][0]['returnValues'][0][0])
    feed_token_ids = list(set(feed_token_ids))
    if len(result['results'][0]['returnValues']) == 2:
        skip_token_ids = convert_vec_u16_to_list(result['results'][0]['returnValues'][1][0])
    else:
        skip_token_ids = []

    return [x for x in feed_token_ids if x not in skip_token_ids]


def core_supply(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun supply(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :param message_raw:
    :param signature:
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    result = dola_protocol.lending_core_bool_adapter.supply.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        bool_global,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        list(bytes.fromhex(signature.replace('0x', ''))),
        init.clock(),
    )
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    status = result['effects']['status']['status']

    executed = False
    if relay_fee >= int(fee_rate * gas):
        executed = True
        result = dola_protocol.lending_core_bool_adapter.supply(
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock(),
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def core_withdraw(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun withdraw(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        bool_message_fee: Coin<SUI>,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    asset_ids = get_feed_tokens_for_relayer_bool(message_raw)
    feed_nums = len(asset_ids)

    if feed_nums > 0:
        left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee, fee_rate)
    else:
        left_relay_fee = relay_fee
        feed_gas = 0

    result = sui_project.batch_transaction_simulate(
        actual_params=[
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock(),
        ],
        transactions=[
            [
                dola_protocol.lending_core_bool_adapter.calc_withdrow_bool_message_fee,
                [
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    list(bytes.fromhex(message_raw.replace('0x', ''))),
                ],
                []
            ],
            [
                dola_protocol.lending_core_bool_adapter.withdraw,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    Argument("Input", U16(5)),
                    Argument("Input", U16(6)),
                    Argument("NestedResult", NestedResult(U16(0), U16(0))),
                    Argument("Input", U16(7)),
                    Argument("Input", U16(8)),
                ],
                []
            ]
        ]
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if left_relay_fee >= int(fee_rate * gas) and status == 'success':
        executed = True
        result = sui_project.batch_transaction(
            actual_params=[
                genesis,
                pool_manager_info,
                user_manager_info,
                bool_global,
                core_state,
                oracle,
                storage,
                list(bytes.fromhex(message_raw.replace('0x', ''))),
                list(bytes.fromhex(signature.replace('0x', ''))),
                init.clock(),
            ],
            transactions=[
                [
                    dola_protocol.lending_core_bool_adapter.calc_withdrow_bool_message_fee,
                    [
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        list(bytes.fromhex(message_raw.replace('0x', ''))),
                    ],
                    []
                ],
                [
                    dola_protocol.lending_core_bool_adapter.withdraw,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("NestedResult", NestedResult(U16(0), U16(0))),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
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


def core_borrow(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun borrow(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        bool_message_fee: Coin<SUI>,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    asset_ids = get_feed_tokens_for_relayer_bool(message_raw)
    feed_nums = len(asset_ids)

    if feed_nums > 0:
        left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee, fee_rate)
    else:
        left_relay_fee = relay_fee
        feed_gas = 0

    result = sui_project.batch_transaction_simulate(
        actual_params=[
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock(),
        ],
        transactions=[
            [
                dola_protocol.lending_core_bool_adapter.calc_withdrow_bool_message_fee,
                [
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    list(bytes.fromhex(message_raw.replace('0x', ''))),
                ],
                []
            ],
            [
                dola_protocol.lending_core_bool_adapter.borrow,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                    Argument("Input", U16(5)),
                    Argument("Input", U16(6)),
                    Argument("NestedResult", NestedResult(U16(0), U16(0))),
                    Argument("Input", U16(7)),
                    Argument("Input", U16(8)),
                ],
                []
            ]
        ]
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if left_relay_fee >= int(fee_rate * gas) and status == 'success':
        executed = True
        result = sui_project.batch_transaction(
            actual_params=[
                genesis,
                pool_manager_info,
                user_manager_info,
                bool_global,
                core_state,
                oracle,
                storage,
                list(bytes.fromhex(message_raw.replace('0x', ''))),
                list(bytes.fromhex(signature.replace('0x', ''))),
                init.clock(),
            ],
            transactions=[
                [
                    dola_protocol.lending_core_bool_adapter.calc_withdrow_bool_message_fee,
                    [
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        list(bytes.fromhex(message_raw.replace('0x', ''))),
                    ],
                    []
                ],
                [
                    dola_protocol.lending_core_bool_adapter.borrow,
                    [
                        Argument("Input", U16(0)),
                        Argument("Input", U16(1)),
                        Argument("Input", U16(2)),
                        Argument("Input", U16(3)),
                        Argument("Input", U16(4)),
                        Argument("Input", U16(5)),
                        Argument("Input", U16(6)),
                        Argument("NestedResult", NestedResult(U16(0), U16(0))),
                        Argument("Input", U16(7)),
                        Argument("Input", U16(8)),
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


def core_repay(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun repay(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    result = dola_protocol.lending_core_bool_adapter.repay.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        bool_global,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        list(bytes.fromhex(signature.replace('0x', ''))),
        init.clock(),
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    status = result['effects']['status']['status']

    executed = False
    if relay_fee >= int(fee_rate * gas):
        executed = True
        result = dola_protocol.lending_core_bool_adapter.repay(
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock(),
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def core_liquidate(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun liquidate(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    asset_ids = get_feed_tokens_for_relayer_bool(message_raw)
    feed_nums = len(asset_ids)

    if feed_nums > 0:
        left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee, fee_rate)
    else:
        left_relay_fee = relay_fee
        feed_gas = 0

    result = sui_project.batch_transaction_simulate(
        actual_params=[
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock(),
        ],
        transactions=[
            [
                dola_protocol.lending_core_bool_adapter.liquidate,
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
    whitelist = [7523, 72, 5]
    if int(result['events'][-1]['parsedJson']["sender_user_id"]) not in whitelist:
        return gas + feed_gas, executed, status, feed_nums, "NotWhiteList"
    elif left_relay_fee >= int(fee_rate * gas) and status == 'success':
        executed = True
        result = sui_project.batch_transaction(
            actual_params=[
                genesis,
                pool_manager_info,
                user_manager_info,
                bool_global,
                core_state,
                oracle,
                storage,
                list(bytes.fromhex(message_raw.replace('0x', ''))),
                list(bytes.fromhex(signature.replace('0x', ''))),
                init.clock(),
            ],
            transactions=[
                [
                    dola_protocol.lending_core_bool_adapter.liquidate,
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


def core_as_collateral(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun as_collateral(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    result = dola_protocol.lending_core_bool_adapter.as_collateral.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        bool_global,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        list(bytes.fromhex(signature.replace('0x', ''))),
        init.clock()
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    status = result['effects']['status']['status']
    executed = False
    if relay_fee >= int(fee_rate * gas):
        executed = True
        dola_protocol.lending_core_bool_adapter.as_collateral(
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock()
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def core_cancel_as_collateral(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public entry fun cancel_as_collateral(
        genesis: &GovernanceGenesis,
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        bool_global: &mut GlobalState,
        core_state: &mut CoreState,
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    oracle = sui_project.network_config['objects']['PriceOracle']
    storage = sui_project.network_config['objects']['LendingStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    asset_ids = get_feed_tokens_for_relayer_bool(message_raw)
    feed_nums = len(asset_ids)

    if feed_nums > 0:
        left_relay_fee, feed_gas = feed_multi_token_price_with_fee(asset_ids, relay_fee, fee_rate)
    else:
        left_relay_fee = relay_fee
        feed_gas = 0

    result = dola_protocol.lending_core_bool_adapter.cancel_as_collateral.simulate(
        genesis,
        pool_manager_info,
        user_manager_info,
        bool_global,
        core_state,
        oracle,
        storage,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        list(bytes.fromhex(signature.replace('0x', ''))),
        init.clock()
    )

    status = result['effects']['status']['status']
    gas = calculate_sui_gas(result['effects']['gasUsed'])
    executed = False
    if left_relay_fee >= int(fee_rate * gas) and status == 'success':
        executed = True
        result = dola_protocol.lending_core_bool_adapter.cancel_as_collateral(
            genesis,
            pool_manager_info,
            user_manager_info,
            bool_global,
            core_state,
            oracle,
            storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
            init.clock()
        )

        return gas + feed_gas, executed, status, feed_nums, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas + feed_gas, executed, result['effects']['status']['error'], feed_nums, ""
    else:
        return gas + feed_gas, executed, status, feed_nums, ""


def core_binding(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public fun bind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        storage: &Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    system_storage = sui_project.network_config['objects']['SystemStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    result = dola_protocol.system_core_bool_adapter.bind_user_address.simulate(
        genesis,
        user_manager_info,
        bool_global,
        core_state,
        system_storage,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        list(bytes.fromhex(signature.replace('0x', ''))),
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])

    status = result['effects']['status']['status']
    executed = False
    if relay_fee >= int(fee_rate * gas):
        executed = True
        result = dola_protocol.system_core_bool_adapter.bind_user_address(
            genesis,
            user_manager_info,
            bool_global,
            core_state,
            system_storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


def core_unbinding(message_raw, signature, relay_fee=0, fee_rate=0.8):
    """
    public fun unbind_user_address(
        genesis: &GovernanceGenesis,
        user_manager_info: &mut UserManagerInfo,
        bool_state: &mut GlobalState,
        core_state: &mut CoreState,
        storage: &Storage,
        message_raw: vector<u8>,
        signature: vector<u8>,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    genesis = sui_project.network_config['objects']['GovernanceGenesis']
    user_manager_info = sui_project.network_config['objects']['UserManagerInfo']
    system_storage = sui_project.network_config['objects']['SystemStorage']

    bool_global = sui_project.network_config['bool_network']['global_state']
    core_state = sui_project.network_config['bool_network']['core_state']

    result = dola_protocol.system_core_bool_adapter.unbind_user_address.simulate(
        genesis,
        user_manager_info,
        bool_global,
        core_state,
        system_storage,
        list(bytes.fromhex(message_raw.replace('0x', ''))),
        list(bytes.fromhex(signature.replace('0x', ''))),
    )

    gas = calculate_sui_gas(result['effects']['gasUsed'])
    status = result['effects']['status']['status']
    executed = False
    if relay_fee >= int(fee_rate * gas):
        executed = True
        result = dola_protocol.system_core_bool_adapter.unbind_user_address(
            genesis,
            user_manager_info,
            bool_global,
            core_state,
            system_storage,
            list(bytes.fromhex(message_raw.replace('0x', ''))),
            list(bytes.fromhex(signature.replace('0x', ''))),
        )
        return gas, executed, status, result['effects']['transactionDigest']
    elif status == 'failure':
        return gas, executed, result['effects']['status']['error'], ""
    else:
        return gas, executed, status, ""


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
