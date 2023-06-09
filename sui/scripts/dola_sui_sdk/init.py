import functools
from typing import List

import requests
# 1e27
import sui_brownie
from sui_brownie import SuiObject, Argument, U16, NestedResult

from dola_sui_sdk import load, sui_project, DOLA_CONFIG, deploy

RAY = 1000000000000000000000000000


# for devnet
def init_wormhole():
    """
    public entry fun complete(
        deployer: DeployerCap,
        upgrade_cap: UpgradeCap,
        governance_chain: u16,
        governance_contract: vector<u8>,
        initial_guardians: vector<vector<u8>>,
        guardian_set_epochs_to_live: u32,
        message_fee: u64,
        ctx: &mut TxContext
    )
    :return:
    """
    wormhole = load.wormhole_package()
    upgrade_cap = load.get_upgrade_cap_by_package_id(wormhole.package_id)

    wormhole.setup.complete(
        wormhole.setup.DeployerCap[-1],
        upgrade_cap,
        0,
        list(bytes.fromhex("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")),
        [
            list(bytes.fromhex("1337133713371337133713371337133713371337")),
            list(bytes.fromhex("c0dec0dec0dec0dec0dec0dec0dec0dec0dec0de")),
            list(bytes.fromhex("ba5edba5edba5edba5edba5edba5edba5edba5ed"))
        ],
        0,
        0
    )


def register_token_price(dola_pool_id, price, decimal):
    """
    public entry fun register_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        dola_pool_id: u16,
        token_price: u64,
        price_decimal: u8
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    dola_protocol.oracle.register_token_price(
        dola_protocol.oracle.OracleCap[-1],
        dola_protocol.oracle.PriceOracle[-1],
        dola_pool_id,
        price,
        decimal
    )


def active_governance_v1():
    """Calls are required by the deployer
    public entry fun activate_governance(
        governance_genesis: &mut GovernanceGenesis,
        governance_info: &mut GovernanceInfo,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    upgrade_cap = load.get_upgrade_cap_by_package_id(dola_protocol.package_id)
    dola_protocol.governance_v1.activate_governance(
        upgrade_cap,
        dola_protocol.governance_v1.GovernanceInfo[-1],
    )


def init_wormhole_adapter_pool():
    """
    public entry fun initialize(
        pool_genesis: &mut PoolGenesis,
        sui_wormhole_chain: u16, // Represents the wormhole chain id of the wormhole adpter core on Sui
        sui_wormhole_address: vector<u8>, // Represents the wormhole contract address of the wormhole adpter core on Sui
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()
    wormhole = load.wormhole_package()

    dola_protocol.wormhole_adapter_pool.initialize(
        dola_protocol.wormhole_adapter_pool.PoolGenesis[-1],
        21,
        get_wormhole_adapter_core_emitter(),
        wormhole.state.State[-1]
    )


def register_owner(vaa):
    """
    public entry fun register_owner(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>
    )
    :return:
    """
    omnipool = load.omnipool_package()

    omnipool.wormhole_adapter_pool.register_owner(
        omnipool.wormhole_adapter_pool.PoolState[-1],
        omnipool.dola_pool.PoolApproval[-1],
        vaa
    )


def delete_owner(vaa):
    """
    public entry fun delete_owner(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>
    )
    :return:
    """
    omnipool = load.omnipool_package()

    omnipool.wormhole_adapter_pool.delete_owner(
        omnipool.wormhole_adapter_pool.PoolState[-1],
        omnipool.dola_pool.PoolApproval[-1],
        vaa
    )


def register_spender(vaa):
    """
    public entry fun register_spender(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>
    )
    :return:
    """
    dola_protocol = load.dola_protocol_package()

    dola_protocol.wormhole_adapter_pool.register_spender(
        dola_protocol.wormhole_adapter_pool.PoolState[-1],
        dola_protocol.dola_pool.PoolApproval[-1],
        list(bytes.fromhex(vaa.replace("0x", "")))
    )


def delete_spender(vaa):
    """
    public entry fun delete_spender(
        pool_state: &PoolState,
        pool_approval: &mut PoolApproval,
        vaa: vector<u8>
    )
    :return:
    """
    omnipool = load.omnipool_package()

    omnipool.wormhole_adapter_pool.delete_spender(
        omnipool.wormhole_adapter_pool.PoolState[-1],
        omnipool.dola_pool.PoolApproval[-1],
        vaa
    )


def create_proposal():
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    dola_protocol = load.dola_protocol_package()
    genesis_proposal.genesis_proposal.create_proposal(
        dola_protocol.governance_v1.GovernanceInfo[-1]
    )


def create_reserve_proposal():
    reserve_proposal = load.reserve_proposal_package()

    governance_info = sui_project.network_config['objects']['GovernanceInfo']
    reserve_proposal.reserve_proposal.create_proposal(
        governance_info
    )


def vote_init_wormhole_adapter_core():
    """
    public entry fun vote_init_wormhole_adapter_core(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_state: &mut State,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    governance = load.governance_package()
    wormhole = load.wormhole_package()

    genesis_proposal.genesis_proposal.vote_init_wormhole_adapter_core(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1]
    )


def vote_init_lending_core():
    """
    public entry fun vote_init_lending_core(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    app_manager = load.app_manager_package()
    governance = load.governance_package()

    genesis_proposal.genesis_proposal.vote_init_lending_core(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        app_manager.app_manager.TotalAppInfo[-1],
    )


def vote_init_system_core():
    """
    public entry fun vote_init_system_core(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    app_manager = load.app_manager_package()
    governance = load.governance_package()

    genesis_proposal.genesis_proposal.vote_init_system_core(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        app_manager.app_manager.TotalAppInfo[-1],
    )


def vote_init_dola_portal():
    """
    public entry fun vote_init_dola_portal(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        dola_contract_registry: &mut DolaContractRegistry,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    governance = load.governance_package()
    dola_types = load.dola_types_package()

    genesis_proposal.genesis_proposal.vote_init_dola_portal(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        dola_types.dola_contract.DolaContractRegistry[-1]
    )


def vote_init_chain_group_id(group_id, chain_ids):
    """
    public entry fun vote_init_chain_group_id(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        user_manager: &mut UserManagerInfo,
        group_id: u16,
        chain_ids: vector<u16>,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    governance = load.governance_package()
    user_manager = load.user_manager_package()
    genesis_proposal.genesis_proposal.vote_init_chain_group_id(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        user_manager.user_manager.UserManagerInfo[-1],
        group_id,
        chain_ids
    )


def vote_remote_register_owner(dola_chain_id, dola_contract):
    """
    public entry fun vote_remote_register_owner(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    wormhole = load.wormhole_package()
    dola_protocol = load.dola_protocol_package()

    genesis_proposal.genesis_proposal.remote_register_owner(
        dola_protocol.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        dola_protocol.wormhole_adapter_core.CoreState[-1],
        dola_chain_id,
        dola_contract,
        0
    )


def vote_remote_delete_owner(dola_chain_id, dola_contract):
    """
    public entry fun vote_remote_delete_owner(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    wormhole = load.wormhole_package()
    dola_protocol = load.dola_protocol_package()

    genesis_proposal.genesis_proposal.remote_delete_owner(
        dola_protocol.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        dola_protocol.wormhole_adapter_core.CoreState[-1],
        dola_chain_id,
        dola_contract,
        0
    )


def vote_remote_register_spender(dola_chain_id, dola_contract):
    """
    public entry fun vote_remote_register_spender(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    wormhole = load.wormhole_package()
    dola_protocol = load.dola_protocol_package()

    result = sui_project.pay_sui([0])
    zero_coin = result['objectChanges'][-1]['objectId']

    genesis_proposal.genesis_proposal.vote_remote_register_spender(
        dola_protocol.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        dola_protocol.wormhole_adapter_core.CoreState[-1],
        dola_chain_id,
        dola_contract,
        zero_coin
    )


def vote_remote_delete_spender(dola_chain_id, dola_contract):
    """
    public entry fun vote_remote_delete_spender(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        wormhole_state: &mut State,
        core_state: &mut CoreState,
        dola_chain_id: u16,
        dola_contract: u256,
        wormhole_message_fee: Coin<SUI>,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    governance = load.governance_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()

    genesis_proposal.genesis_proposal.vote_remote_delete_spender(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
        dola_chain_id,
        dola_contract,
        0
    )


def vote_register_new_pool(pool_id, pool_name, coin_type, dst_chain=0):
    """
    public entry fun vote_register_new_pool(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_address: vector<u8>,
        pool_dola_chain_id: u16,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        weight: u256,
        ctx: &mut TxContext
    )
    :return:
    """
    if isinstance(coin_type, str):
        if "0x" in coin_type[:2] and dst_chain != 1:
            coin_type = coin_type[2:]

        if dst_chain not in [0, 1]:
            coin_type = coin_type.lower()

        if dst_chain in [0, 1]:
            coin_type = list(bytes(coin_type, "ascii"))
        else:
            # for eth, use hex string
            coin_type = list(bytes.fromhex(coin_type))
    genesis_proposal = load.genesis_proposal_package()
    governance = load.governance_package()
    pool_manager = load.pool_manager_package()
    genesis_proposal.genesis_proposal.vote_register_new_pool(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        pool_manager.pool_manager.PoolManagerInfo[-1],
        coin_type,
        dst_chain,
        list(pool_name),
        pool_id,
        1
    )


def claim_test_coin(coin_type):
    test_coins = load.test_coins_package()
    test_coins.faucet.claim(
        test_coins.faucet.Faucet[-1],
        type_arguments=[coin_type]
    )


def force_claim_test_coin(coin_type, amount):
    test_coins = load.test_coins_package()
    test_coins.faucet.force_claim(
        test_coins.faucet.Faucet[-1],
        int(amount),
        type_arguments=[coin_type]
    )


def add_test_coins_admin(address):
    test_coins = load.test_coins_package()
    test_coins.faucet.add_admin(
        test_coins.faucet.Faucet[-1],
        address,
    )


def usdt():
    return sui_project.network_config['tokens']['USDT']


def usdc():
    return sui_project.network_config['tokens']['USDC']


def weth():
    return sui_project.network_config['tokens']['WETH']


def sui():
    return sui_project.network_config['tokens']['SUI']


def clock():
    return sui_project.network_config['objects']['Clock']


def coin(coin_type):
    return f"0x2::coin::Coin<{coin_type}>"


def balance(coin_type):
    return f"0x2::balance::Supply<{coin_type}>"


def pool(coin_type):
    if "sui::SUI" in coin_type:
        return f"{sui_project.DolaProtocol[-1]}::dola_pool::Pool<0x2::sui::SUI>"
    else:
        return f"{sui_project.DolaProtocol[-1]}::dola_pool::Pool<{coin_type}>"


def pool_id(coin_type):
    coin_name = coin_type.split("::")[-1]
    return sui_project.network_config['objects'][f"Pool<{coin_name}>"]


def proposal():
    dola_protocol = sui_project.network_config['packages']['dola_protocol']
    genesis_proposal = sui_project.network_config['packages']['genesis_proposal']
    return f"{dola_protocol}::governance_v1::Proposal<{genesis_proposal}" \
           f"::genesis_proposal::Certificate>"


def query_portal_relay_event(limit=10):
    dola_protocol = "0x826915f8ca6d11597dfe6599b8aa02a4c08bd8d39674855254a06ee83fe7220e"
    return sui_project.client.suix_queryEvents(
        {"MoveEventType": f"{dola_protocol}::lending_portal::RelayEvent"}, limit=limit,
        cursor=None, descending_order=True)['data']


def query_core_relay_event(limit=10):
    dola_protocol = "0x826915f8ca6d11597dfe6599b8aa02a4c08bd8d39674855254a06ee83fe7220e"
    return sui_project.client.suix_queryEvents(
        {"MoveEventType": f"{dola_protocol}::lending_core_wormhole_adapter::RelayEvent"}, limit=limit,
        cursor=None, descending_order=True)['data']


@functools.lru_cache()
def get_wormhole_adapter_core_emitter() -> List[int]:
    dola_protocol = load.dola_protocol_package()
    result = sui_project.client.sui_getObject(
        dola_protocol.wormhole_adapter_core.CoreState[-1],
        {
            "showType": True,
            "showOwner": True,
            "showPreviousTransaction": False,
            "showDisplay": False,
            "showContent": True,
            "showBcs": False,
            "showStorageRebate": False
        }
    )

    return list(bytes.fromhex(result["data"]["content"]["fields"]["wormhole_emitter"]["fields"]["id"]["id"][2:]))


@functools.lru_cache()
def get_wormhole_adapter_pool_emitter() -> List[int]:
    result = sui_project.client.sui_getObject(
        sui_project.network_config['objects']['PoolState'],
        {
            "showType": True,
            "showOwner": True,
            "showPreviousTransaction": False,
            "showDisplay": False,
            "showContent": True,
            "showBcs": False,
            "showStorageRebate": False
        }
    )

    return list(bytes.fromhex(result["data"]["content"]["fields"]["wormhole_emitter"]["fields"]["id"]["id"][2:]))


def format_emitter_address(addr):
    addr = addr.replace("0x", "")
    if len(addr) < 64:
        addr = "0" * (64 - len(addr)) + addr
    return addr


def hex_to_vector(hex_str: str):
    return list(bytes.fromhex(hex_str.replace("0x", "")))


def coin_type_to_vector(coin_type: str):
    return list(bytes(coin_type.replace("0x", ""), "ascii"))


def register_remote_bridge(wormhole_chain_id, emitter_address):
    genesis_proposal = load.genesis_proposal_package()
    dola_protocol = load.dola_protocol_package()

    emitter_address = format_emitter_address(emitter_address)

    create_proposal()

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
    ]

    bridge_params = [
        sui_project.network_config['objects']['CoreState'],
        wormhole_chain_id,
        list(bytes.fromhex(emitter_address.replace("0x", ""))),
    ]

    sui_project.batch_transaction(
        actual_params=basic_params + bridge_params,
        transactions=[
            [
                genesis_proposal.genesis_proposal.vote_proposal_final,
                [
                    Argument("Input", U16(0)), Argument("Input", U16(1))
                ],
                []
            ],
            [
                genesis_proposal.genesis_proposal.register_remote_bridge,
                [
                    Argument("NestedResult", NestedResult(U16(0), U16(0))),
                    Argument("NestedResult", NestedResult(U16(0), U16(1))),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                ],
                []
            ],
            [
                genesis_proposal.genesis_proposal.destory,
                [
                    Argument("NestedResult", NestedResult(U16(1), U16(0))),
                    Argument("NestedResult", NestedResult(U16(1), U16(1)))
                ],
                []
            ]
        ]
    )


def delete_remote_bridge(wormhole_chain_id):
    genesis_proposal = load.genesis_proposal_package()
    dola_protocol = load.dola_protocol_package()

    create_proposal()

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
    ]

    bridge_params = [
        sui_project.network_config['objects']['CoreState'],
        wormhole_chain_id,
    ]

    sui_project.batch_transaction(
        actual_params=basic_params + bridge_params,
        transactions=[
            [
                genesis_proposal.genesis_proposal.vote_proposal_final,
                [
                    Argument("Input", U16(0)), Argument("Input", U16(1))
                ],
                []
            ],
            [
                genesis_proposal.genesis_proposal.delete_remote_bridge,
                [
                    Argument("NestedResult", NestedResult(U16(0), U16(0))),
                    Argument("NestedResult", NestedResult(U16(0), U16(1))),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                ],
                []
            ],
            [
                genesis_proposal.genesis_proposal.destory,
                [
                    Argument("NestedResult", NestedResult(U16(1), U16(0))),
                    Argument("NestedResult", NestedResult(U16(1), U16(1)))
                ],
                []
            ]
        ]
    )


def build_vote_proposal_final_tx_block(genesis_proposal):
    return [[
        genesis_proposal.genesis_proposal.vote_proposal_final,
        [Argument("Input", U16(0)), Argument("Input", U16(1))],
        []
    ]]


def build_reserve_proposal_final_tx_block(genesis_proposal):
    return [[
        genesis_proposal.reserve_proposal.vote_proposal_final,
        [Argument("Input", U16(0)), Argument("Input", U16(1))],
        []
    ]]


def build_finish_proposal_tx_block(genesis_proposal, tx_block_num):
    return [[
        genesis_proposal.genesis_proposal.destory,
        [
            Argument("NestedResult", NestedResult(U16(tx_block_num), U16(0))),
            Argument("NestedResult", NestedResult(U16(tx_block_num), U16(1)))
        ],
        []
    ]]


def build_reserve_proposal_tx_block(genesis_proposal, tx_block_num):
    return [[
        genesis_proposal.reserve_proposal.destory,
        [
            Argument("NestedResult", NestedResult(U16(tx_block_num), U16(0))),
            Argument("NestedResult", NestedResult(U16(tx_block_num), U16(1)))
        ],
        []
    ]]


def build_register_new_pool_tx_block(genesis_proposal, basic_param_num, sequence):
    return [
        genesis_proposal.genesis_proposal.register_new_pool,
        [
            Argument("NestedResult", NestedResult(U16(sequence), U16(0))),
            Argument("NestedResult", NestedResult(U16(sequence), U16(1))),
            Argument("Input", U16(basic_param_num - 1)),
            Argument("Input", U16(basic_param_num + 5 * sequence + 0)),
            Argument("Input", U16(basic_param_num + 5 * sequence + 1)),
            Argument("Input", U16(basic_param_num + 5 * sequence + 2)),
            Argument("Input", U16(basic_param_num + 5 * sequence + 3)),
            Argument("Input", U16(basic_param_num + 5 * sequence + 4)),
        ],
        []
    ]


def build_register_new_reserve_tx_block(genesis_proposal, basic_param_num, sequence):
    return [
        genesis_proposal.genesis_proposal.register_new_reserve,
        [Argument("NestedResult", NestedResult(U16(sequence), U16(0))),
         Argument("NestedResult", NestedResult(U16(sequence), U16(1))),
         Argument("Input", U16(basic_param_num - 2)),
         Argument("Input", U16(basic_param_num - 1)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 0)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 1)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 2)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 3)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 4)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 5)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 6)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 7)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 8)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 9)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 10)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 11)),
         Argument("Input", U16(basic_param_num + 13 * sequence + 12)),
         ],
        []
    ]


def batch_execute_proposal():
    genesis_proposal = load.genesis_proposal_package()
    dola_protocol = load.dola_protocol_package()

    # Execute genesis proposal

    # init_wormhole_adapter_core
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    create_proposal()

    init_wormhole_adapter_core_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        wormhole_state,  # 2
    ]

    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    init_wormhole_adapter_core_tx_block = [[
        genesis_proposal.genesis_proposal.init_wormhole_adapter_core,
        [
            Argument("NestedResult", NestedResult(U16(0), U16(0))),
            Argument("NestedResult", NestedResult(U16(0), U16(1))),
            Argument("Input", U16(2))
        ],
        []
    ]]

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, 1)

    sui_project.batch_transaction(
        actual_params=init_wormhole_adapter_core_params,
        transactions=vote_proposal_final_tx_block + init_wormhole_adapter_core_tx_block + finish_proposal_tx_block
    )

    # Use core state
    init_wormhole_adapter_pool()

    # Init poolmanager params
    # pool_address, dola_chain_id, pool_name, dola_pool_id, pool_weight

    create_proposal()

    pool_params = []

    for pool in sui_project.network_config['pools']:
        pool_address = sui_project.network_config['pools'][pool]['pool_address']
        dola_chain_id = sui_project.network_config['pools'][pool]['dola_chain_id']
        pool_name = sui_project.network_config['pools'][pool]['pool_name']
        dola_pool_id = sui_project.network_config['pools'][pool]['dola_pool_id']
        pool_weight = sui_project.network_config['pools'][pool]['pool_weight']
        pool_params.extend([coin_type_to_vector(pool_address), dola_chain_id, coin_type_to_vector(pool_name),
                            dola_pool_id, pool_weight])

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        dola_protocol.pool_manager.PoolManagerInfo[-1],  # 2
    ]

    pool_num = len(pool_params) // 5
    register_new_pool_tx_blocks = [
        build_register_new_pool_tx_block(genesis_proposal, len(basic_params), i) for i in range(pool_num)
    ]
    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, pool_num)

    sui_project.batch_transaction(
        actual_params=basic_params + pool_params,
        transactions=vote_proposal_final_tx_block + register_new_pool_tx_blocks + finish_proposal_tx_block
    )

    # Init chain group id param
    chain_group_id = 2
    group_chain_ids = [5, 23]

    create_proposal()
    sui_project.batch_transaction(
        actual_params=[dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
                       sui_project[SuiObject.from_type(proposal())][-1],  # 1
                       dola_protocol.app_manager.TotalAppInfo[-1],  # 2
                       dola_protocol.user_manager.UserManagerInfo[-1],  # 3
                       chain_group_id,  # 4
                       group_chain_ids,  # 5
                       ],
        transactions=[
            [genesis_proposal.genesis_proposal.vote_proposal_final,
             [Argument("Input", U16(0)), Argument("Input", U16(1))],
             []
             ],  # 0. vote_proposal_final
            [
                genesis_proposal.genesis_proposal.init_system_core,
                [Argument("NestedResult", NestedResult(U16(0), U16(0))),
                 Argument("NestedResult", NestedResult(U16(0), U16(1))),
                 Argument("Input", U16(2))],
                []
            ],  # 1. init_system_core
            [
                genesis_proposal.genesis_proposal.init_lending_core,
                [Argument("NestedResult", NestedResult(U16(1), U16(0))),
                 Argument("NestedResult", NestedResult(U16(1), U16(1))),
                 Argument("Input", U16(2))],
                []
            ],  # 2. init_lending_core
            [
                genesis_proposal.genesis_proposal.init_chain_group_id,
                [Argument("NestedResult", NestedResult(U16(2), U16(0))),
                 Argument("NestedResult", NestedResult(U16(2), U16(1))),
                 Argument("Input", U16(3)),
                 Argument("Input", U16(4)),
                 Argument("Input", U16(5))],
                []
            ],  # 3. init_chain_group_id
            [genesis_proposal.genesis_proposal.destory,
             [Argument("NestedResult", NestedResult(U16(3), U16(0))),
              Argument("NestedResult", NestedResult(U16(3), U16(1)))],
             []
             ]
        ]
    )

    # Init lending reserve

    # reserve params
    # [dola_pool_id, is_isolated_asset, borrowable_in_isolation, treasury,
    # treasury_factor, borrow_cap_ceiling, collateral_coefficient, borrow_coefficient,
    # base_borrow_rate, borrow_rate_slope1, borrow_rate_slope2, optimal_utilization]
    create_proposal()

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        dola_protocol.lending_core_storage.Storage[-1],  # 2
        clock()  # 3
    ]

    reserve_params = []
    reserves_num = len(sui_project.network_config['reserves'])

    for reserve in sui_project.network_config['reserves']:
        reserve_pool_id = sui_project.network_config['reserves'][reserve]['dola_pool_id']
        reserve_is_isolated_asset = sui_project.network_config['reserves'][reserve]['is_isolated_asset']
        reserve_borrowable_in_isolation = sui_project.network_config['reserves'][reserve]['borrowable_in_isolation']
        reserve_treasury = sui_project.network_config['reserves'][reserve]['treasury']
        reserve_treasury_factor = int(sui_project.network_config['reserves'][reserve]['treasury_factor'] * RAY)
        reserve_supply_cap_ceiling = int(sui_project.network_config['reserves'][reserve]['supply_cap_ceiling'] * 1e8)
        reserve_borrow_cap_ceiling = int(sui_project.network_config['reserves'][reserve]['borrow_cap_ceiling'] * 1e8)
        reserve_collateral_coefficient = int(
            sui_project.network_config['reserves'][reserve]['collateral_coefficient'] * RAY)
        reserve_borrow_coefficient = int(sui_project.network_config['reserves'][reserve]['borrow_coefficient'] * RAY)
        reserve_base_borrow_rate = int(sui_project.network_config['reserves'][reserve]['base_borrow_rate'] * RAY)
        reserve_borrow_rate_slope1 = int(sui_project.network_config['reserves'][reserve]['borrow_rate_slope1'] * RAY)
        reserve_borrow_rate_slope2 = int(sui_project.network_config['reserves'][reserve]['borrow_rate_slope2'] * RAY)
        reserve_optimal_utilization = int(sui_project.network_config['reserves'][reserve]['optimal_utilization'] * RAY)
        reserve_param = [reserve_pool_id, reserve_is_isolated_asset, reserve_borrowable_in_isolation, reserve_treasury,
                         reserve_treasury_factor, reserve_supply_cap_ceiling, reserve_borrow_cap_ceiling,
                         reserve_collateral_coefficient,
                         reserve_borrow_coefficient, reserve_base_borrow_rate, reserve_borrow_rate_slope1,
                         reserve_borrow_rate_slope2, reserve_optimal_utilization]
        reserve_params.extend(reserve_param)

    register_new_reserve_tx_blocks = []
    for i in range(reserves_num):
        register_new_reserve_tx_block = build_register_new_reserve_tx_block(genesis_proposal, len(basic_params), i)
        register_new_reserve_tx_blocks.append(register_new_reserve_tx_block)

    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, reserves_num)

    actual_params = basic_params + reserve_params
    transactions = vote_proposal_final_tx_block + register_new_reserve_tx_blocks + finish_proposal_tx_block

    sui_project.batch_transaction(
        actual_params=actual_params,
        transactions=transactions
    )


def register_new_reserve(reserve: str = "MATIC"):
    genesis_proposal = load.genesis_proposal_package()
    create_proposal()

    governance_info = sui_project.network_config['objects']['GovernanceInfo']
    lending_storage = sui_project.network_config['objects']['LendingStorage']

    basic_params = [
        governance_info,  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        lending_storage,  # 2
        clock()  # 3
    ]

    reserve_pool_id = sui_project.network_config['reserves'][reserve]['dola_pool_id']
    reserve_is_isolated_asset = sui_project.network_config['reserves'][reserve]['is_isolated_asset']
    reserve_borrowable_in_isolation = sui_project.network_config['reserves'][reserve]['borrowable_in_isolation']
    reserve_treasury = sui_project.network_config['reserves'][reserve]['treasury']
    reserve_treasury_factor = int(sui_project.network_config['reserves'][reserve]['treasury_factor'] * RAY)
    reserve_supply_cap_ceiling = int(sui_project.network_config['reserves'][reserve]['supply_cap_ceiling'] * 1e8)
    reserve_borrow_cap_ceiling = int(sui_project.network_config['reserves'][reserve]['borrow_cap_ceiling'] * 1e8)
    reserve_collateral_coefficient = int(
        sui_project.network_config['reserves'][reserve]['collateral_coefficient'] * RAY)
    reserve_borrow_coefficient = int(sui_project.network_config['reserves'][reserve]['borrow_coefficient'] * RAY)
    reserve_base_borrow_rate = int(sui_project.network_config['reserves'][reserve]['base_borrow_rate'] * RAY)
    reserve_borrow_rate_slope1 = int(sui_project.network_config['reserves'][reserve]['borrow_rate_slope1'] * RAY)
    reserve_borrow_rate_slope2 = int(sui_project.network_config['reserves'][reserve]['borrow_rate_slope2'] * RAY)
    reserve_optimal_utilization = int(sui_project.network_config['reserves'][reserve]['optimal_utilization'] * RAY)
    reserve_param = [reserve_pool_id, reserve_is_isolated_asset, reserve_borrowable_in_isolation, reserve_treasury,
                     reserve_treasury_factor, reserve_supply_cap_ceiling, reserve_borrow_cap_ceiling,
                     reserve_collateral_coefficient,
                     reserve_borrow_coefficient, reserve_base_borrow_rate, reserve_borrow_rate_slope1,
                     reserve_borrow_rate_slope2, reserve_optimal_utilization]
    reserve_params = list(reserve_param)
    register_new_reserve_tx_block = build_register_new_reserve_tx_block(genesis_proposal, len(basic_params), 0)
    register_new_reserve_tx_blocks = [register_new_reserve_tx_block]
    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, 1)

    actual_params = basic_params + reserve_params
    transactions = vote_proposal_final_tx_block + register_new_reserve_tx_blocks + finish_proposal_tx_block

    sui_project.batch_transaction(
        actual_params=actual_params,
        transactions=transactions
    )


def get_price(symbol):
    pyth_service_url = sui_project.network_config['pyth_service_url']
    feed_id = sui_project.network_config['oracle']['feed_id'][symbol].replace("0x", "")
    url = f"{pyth_service_url}/api/latest_price_feeds?ids[]={feed_id}"
    response = requests.get(url)
    result = response.json()
    price = int(result[0]['ema_price']['price'])
    decimal = int(result[0]['ema_price']['expo']).__abs__()
    return price, decimal


def build_create_pool_tx_block(dola_protocol, sequence, coin_type):
    return [
        dola_protocol.dola_pool.create_pool,
        [
            Argument('Input', U16(sequence))
        ],
        [coin_type]
    ]


def batch_create_pool():
    dola_protocol = load.dola_protocol_package()

    sui_metadata = sui_project.client.suix_getCoinMetadata(sui()['coin_type'])['id']
    usdt_metadata = sui_project.client.suix_getCoinMetadata(usdt()['coin_type'])['id']
    usdc_metadata = sui_project.client.suix_getCoinMetadata(usdc()['coin_type'])['id']

    create_pool_params = [sui_metadata, usdt_metadata, usdc_metadata]
    coin_types = [sui()['coin_type'], usdt()['coin_type'], usdc()['coin_type']]
    create_pool_tx_blocks = [
        build_create_pool_tx_block(dola_protocol, i, coin_types[i])
        for i in range(len(create_pool_params))
    ]
    sui_project.batch_transaction(
        actual_params=create_pool_params,
        transactions=create_pool_tx_blocks
    )


def build_register_token_price_tx_block(genesis_proposal, basic_param_num, sequence):
    return [
        genesis_proposal.genesis_proposal.register_token_price,
        [
            Argument("NestedResult", NestedResult(U16(sequence), U16(0))),
            Argument("NestedResult", NestedResult(U16(sequence), U16(1))),
            Argument("Input", U16(basic_param_num - 2)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 0)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 1)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 2)),
            Argument("Input", U16(basic_param_num + sequence * 4 + 3)),
            Argument("Input", U16(basic_param_num - 1)),
        ],
        []
    ]


def batch_init_oracle():
    genesis_proposal = load.genesis_proposal_package()
    dola_protocol = load.dola_protocol_package()

    create_proposal()

    btc_token_param = construct_register_token_price_param(
        "BTC/USD", 'BTC'
    )
    usdt_token_param = construct_register_token_price_param(
        "USDT/USD", 'USDT'
    )
    usdc_token_param = construct_register_token_price_param(
        "USDC/USD", 'USDC'
    )
    sui_token_param = construct_register_token_price_param(
        "SUI/USD", 'SUI'
    )
    eth_token_param = construct_register_token_price_param(
        "ETH/USD", 'ETH'
    )
    matic_token_param = construct_register_token_price_param(
        "MATIC/USD", 'MATIC'
    )

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        dola_protocol.oracle.PriceOracle[-1],  # 2
        clock(),  # 3
    ]

    token_params = btc_token_param + usdt_token_param + usdc_token_param + sui_token_param + eth_token_param + matic_token_param

    token_nums = len(token_params) // 4
    register_token_price_tx_blocks = [
        build_register_token_price_tx_block(
            genesis_proposal, len(basic_params), i
        )
        for i in range(token_nums)
    ]
    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, token_nums)

    sui_project.batch_transaction(
        actual_params=basic_params + token_params,
        transactions=vote_proposal_final_tx_block + register_token_price_tx_blocks + finish_proposal_tx_block
    )


def construct_register_token_price_param(symbol, token_name):
    # use pyth oracle price to init oracle
    # Token price params
    # [dola_pool_id, price, price_decimal]
    (btc_price, btc_price_decimal) = get_price(symbol)
    btc_dola_pool_id = sui_project.network_config['reserves'][token_name]['dola_pool_id']
    btc_feed_id = hex_to_vector(
        sui_project.network_config['oracle']['feed_id'][symbol]
    )
    return [btc_dola_pool_id, btc_feed_id, btc_price, btc_price_decimal]


def upgrade_evm_adapter(dola_chain_id, new_dola_contract, old_dola_contract):
    # 1. deploy new evm adapter
    # 2. remote register new owner
    genesis_proposal = load.genesis_proposal_package()

    # create_proposal()

    governance_info = sui_project.network_config['objects']['GovernanceInfo']
    wormhole_state = sui_project.network_config['objects']['WormholeState']
    core_state = sui_project.network_config['objects']['CoreState']

    result = sui_project.pay_sui([0])
    zero_coin = [coin['reference']['objectId'] for coin in result['effects']['created']][0]

    basic_params = [
        governance_info,  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        wormhole_state,  # 2
        core_state,  # 3
        zero_coin,  # 4
        clock(),  # 5
    ]

    contract_params = [
        dola_chain_id,  # 6
        new_dola_contract,  # 7
    ]

    remote_register_owner = [
        genesis_proposal.genesis_proposal.remote_register_owner,
        [
            Argument("NestedResult", NestedResult(U16(0), U16(0))),
            Argument("NestedResult", NestedResult(U16(0), U16(1))),
            Argument("Input", U16(2)),
            Argument("Input", U16(3)),
            Argument("Input", U16(6)),
            Argument("Input", U16(7)),
            Argument("Input", U16(4)),
            Argument("Input", U16(5)),
        ],
        []
    ]

    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, 1)

    sui_project.batch_transaction(
        actual_params=basic_params + contract_params,
        transactions=vote_proposal_final_tx_block + [remote_register_owner] + finish_proposal_tx_block
    )

    # 3. remote remove old owner
    create_proposal()

    result = sui_project.pay_sui([0])
    zero_coin = [coin['reference']['objectId'] for coin in result['effects']['created']][0]

    basic_params = [
        governance_info,  # 0
        sui_project[SuiObject.from_type(proposal())][-1],  # 1
        wormhole_state,  # 2
        core_state,  # 3
        zero_coin,  # 4
        clock(),  # 5
    ]

    contract_params = [
        dola_chain_id,  # 6
        old_dola_contract,  # 7
    ]

    remote_delete_owner = [
        genesis_proposal.genesis_proposal.remote_delete_owner,
        [
            Argument("NestedResult", NestedResult(U16(0), U16(0))),
            Argument("NestedResult", NestedResult(U16(0), U16(1))),
            Argument("Input", U16(2)),
            Argument("Input", U16(3)),
            Argument("Input", U16(6)),
            Argument("Input", U16(7)),
            Argument("Input", U16(4)),
            Argument("Input", U16(5)),
        ],
        []
    ]

    vote_proposal_final_tx_block = build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = build_finish_proposal_tx_block(genesis_proposal, 1)

    sui_project.batch_transaction(
        actual_params=basic_params + contract_params,
        transactions=vote_proposal_final_tx_block + [remote_delete_owner] + finish_proposal_tx_block
    )


def deploy_reserve_proposal():
    dola_protocol = sui_project.network_config['packages']['dola_protocol']
    reserve_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            "proposals/reserve_params_proposal")
    )

    reserve_proposal_package.program_publish_package(replace_address=dict(
        dola_protocol=dola_protocol,
    ))

    deploy.export_package_to_config('reserve_proposal', reserve_proposal_package.package_id)


def set_reserve_coefficient(reserve: str = 'SUI'):
    reserve_proposal = load.reserve_proposal_package()
    dola_protocol = load.dola_protocol_package()

    create_reserve_proposal()

    governance_info = sui_project.network_config['objects']['GovernanceInfo']
    certificate = f"{dola_protocol.package_id}::governance_v1::Proposal<{reserve_proposal.package_id}" \
                  f"::reserve_proposal::Certificate>"
    proposal_id = sui_project[SuiObject.from_type(certificate)][-1]
    lending_storage = sui_project.network_config['objects']['LendingStorage']

    basic_params = [
        governance_info,  # 0
        proposal_id,  # 1
        lending_storage,  # 2
    ]

    dola_pool_id = int(sui_project.network_config['reserves'][reserve]['dola_pool_id'])
    reserve_borrow_coefficient = int(sui_project.network_config['reserves'][reserve]['borrow_coefficient'] * RAY)
    reserve_collateral_coefficient = int(
        sui_project.network_config['reserves'][reserve]['collateral_coefficient'] * RAY)

    reserve_params = [
        dola_pool_id,  # 3
        reserve_borrow_coefficient,  # 4
        reserve_collateral_coefficient,  # 5
    ]

    set_borrow_coefficient_tx_block = [
        reserve_proposal.reserve_proposal.set_borrow_coefficient,
        [
            Argument("NestedResult", NestedResult(U16(0), U16(0))),
            Argument("NestedResult", NestedResult(U16(0), U16(1))),
            Argument("Input", U16(2)),
            Argument("Input", U16(3)),
            Argument("Input", U16(4))
        ],
        []
    ]

    set_collateral_coefficient_tx_block = [
        reserve_proposal.reserve_proposal.set_collateral_coefficient,
        [
            Argument("NestedResult", NestedResult(U16(1), U16(0))),
            Argument("NestedResult", NestedResult(U16(1), U16(1))),
            Argument("Input", U16(2)),
            Argument("Input", U16(3)),
            Argument("Input", U16(5))
        ],
        []
    ]

    set_coefficient_tx_block = [set_borrow_coefficient_tx_block, set_collateral_coefficient_tx_block]

    vote_proposal_final_tx_block = build_reserve_proposal_final_tx_block(reserve_proposal)

    finish_proposal_tx_block = build_reserve_proposal_tx_block(reserve_proposal, 2)

    actual_params = basic_params + reserve_params
    transactions = vote_proposal_final_tx_block + set_coefficient_tx_block + finish_proposal_tx_block

    sui_project.batch_transaction(
        actual_params=actual_params,
        transactions=transactions
    )


def set_is_isolated_asset(reserve):
    reserve_proposal = load.reserve_proposal_package()
    dola_protocol = load.dola_protocol_package()

    create_reserve_proposal()

    governance_info = sui_project.network_config['objects']['GovernanceInfo']
    certificate = f"{dola_protocol.package_id}::governance_v1::Proposal<{reserve_proposal.package_id}" \
                  f"::reserve_proposal::Certificate>"
    proposal_id = sui_project[SuiObject.from_type(certificate)][-1]
    lending_storage = sui_project.network_config['objects']['LendingStorage']

    basic_params = [
        governance_info,  # 0
        proposal_id,  # 1
        lending_storage,  # 2
    ]

    dola_pool_id = int(sui_project.network_config['reserves'][reserve]['dola_pool_id'])
    reserve_is_isolated_asset = sui_project.network_config['reserves'][reserve]['is_isolated_asset']

    reserve_params = [
        dola_pool_id,  # 3
        reserve_is_isolated_asset,  # 4
    ]

    set_is_isolated_asset_tx_block = [
        reserve_proposal.reserve_proposal.set_is_isolated_asset,
        [
            Argument("NestedResult", NestedResult(U16(0), U16(0))),
            Argument("NestedResult", NestedResult(U16(0), U16(1))),
            Argument("Input", U16(2)),
            Argument("Input", U16(3)),
            Argument("Input", U16(4))
        ],
        []
    ]

    vote_proposal_final_tx_block = build_reserve_proposal_final_tx_block(reserve_proposal)

    finish_proposal_tx_block = build_reserve_proposal_tx_block(reserve_proposal, 1)

    actual_params = basic_params + reserve_params
    transactions = vote_proposal_final_tx_block + [set_is_isolated_asset_tx_block] + finish_proposal_tx_block

    sui_project.batch_transaction(
        actual_params=actual_params,
        transactions=transactions
    )


def batch_init():
    active_governance_v1()
    batch_init_oracle()
    batch_create_pool()
    batch_execute_proposal()


if __name__ == '__main__':
    batch_init()

    # delete_remote_bridge(5)
    # register_remote_bridge(5, "0x1FFBE74B4665037070E734daf9F79fa33B6d54a8")
    # sui_pool_emitter = bytes(get_wormhole_adapter_pool_emitter()).hex()
    # register_remote_bridge(0, sui_pool_emitter)

    # deploy_reserve_proposal()
    # set_reserve_coefficient("SUI")
    # set_is_isolated_asset("SUI")
    # register_new_reserve(reserve="MATIC")
