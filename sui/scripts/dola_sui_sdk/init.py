import functools

from dola_sui_sdk import load, sui_project
# 1e27
from sui_brownie import SuiObject

RAY = 1000000000000000000000000000

net = "sui-testnet"


def create_pool(coin_type):
    omnipool = load.omnipool_package()
    omnipool.dola_pool.create_pool(8, type_arguments=[coin_type])


@functools.lru_cache()
def get_upgrade_cap_info(upgrade_cap_ids: tuple):
    result = sui_project.client.sui_multiGetObjects(
        upgrade_cap_ids,
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
    return {v["data"]["content"]["fields"]["package"]: v["data"] for v in result}


def get_upgrade_cap_by_package_id(package_id: str):
    upgrade_cap_ids = tuple(list(sui_project["0x2::package::UpgradeCap"]))
    info = get_upgrade_cap_info(upgrade_cap_ids)
    if package_id in info:
        return info[package_id]["objectId"]


def init_wormhole():
    """
    public entry fun init_and_share_state(
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

    wormhole.setup.init_and_share_state(
        wormhole.setup.DeployerCap[-1],
        get_upgrade_cap_by_package_id(wormhole.package_id),
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
    oracle = load.oracle_package()

    oracle.oracle.register_token_price(
        oracle.oracle.OracleCap[-1],
        oracle.oracle.PriceOracle[-1],
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
    governance = load.governance_package()
    governance.governance_v1.activate_governance(
        governance.genesis.GovernanceGenesis[-1],
        governance.governance_v1.GovernanceInfo[-1],
    )


def init_wormhole_adapter_pool():
    """
    public entry fun initialize(
        pool_genesis: &mut PoolGenesis,
        sui_wormhole_chain: u16, // Represents the wormhole chain id of the wormhole adpter core on Sui
        sui_wormhole_address: vector<u8>, // Represents the wormhole contract address of the wormhole adpter core on Sui
        pool_approval: &mut PoolApproval,
        dola_contract_registry: &mut DolaContractRegistry,
        wormhole_state: &mut WormholeState,
        ctx: &mut TxContext
    )
    :return:
    """
    omnipool = load.omnipool_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    dola_types = load.dola_types_package()

    omnipool.wormhole_adapter_pool.initialize(
        omnipool.wormhole_adapter_pool.PoolGenesis[-1],
        0,
        list(bytes.fromhex(wormhole_adapter_core.package_id.removeprefix("0x"))),
        omnipool.dola_pool.PoolApproval[-1],
        dola_types.dola_contract.DolaContractRegistry[-1],
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
    omnipool = load.omnipool_package()

    omnipool.wormhole_adapter_pool.register_spender(
        omnipool.wormhole_adapter_pool.PoolState[-1],
        omnipool.dola_pool.PoolApproval[-1],
        vaa
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
    governance = load.governance_package()
    genesis_proposal.genesis_proposal.create_proposal(
        governance.governance_v1.GovernanceInfo[-1])


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
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        wormhole_adapater: &mut lending_core::wormhole_adapter::WormholeAdapter,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    app_manager = load.app_manager_package()
    governance = load.governance_package()
    lending_core = load.lending_core_package()

    genesis_proposal.genesis_proposal.vote_init_lending_core(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        lending_core.storage.Storage[-1],
        app_manager.app_manager.TotalAppInfo[-1],
        lending_core.wormhole_adapter.WormholeAdapter[-1]
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
    governance = load.governance_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()

    genesis_proposal.genesis_proposal.vote_remote_register_owner(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
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
    governance = load.governance_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()

    genesis_proposal.genesis_proposal.vote_remote_delete_owner(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
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
    governance = load.governance_package()
    wormhole = load.wormhole_package()
    wormhole_adapter_core = load.wormhole_adapter_core_package()

    result = sui_project.pay_sui([0])
    zero_coin = result['objectChanges'][-1]['objectId']

    genesis_proposal.genesis_proposal.vote_remote_register_spender(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        wormhole.state.State[-1],
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1],
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


def vote_register_new_reserve(dola_pool_id):
    """
    public entry fun vote_register_new_reserve(
        governance_info: &mut GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        clock: &Clock,
        dola_pool_id: u16,
        is_isolated_asset: bool,
        borrowable_in_isolation: bool,
        treasury: u64,
        treasury_factor: u256,
        borrow_cap_ceiling: u256,
        collateral_coefficient: u256,
        borrow_coefficient: u256,
        base_borrow_rate: u256,
        borrow_rate_slope1: u256,
        borrow_rate_slope2: u256,
        optimal_utilization: u256,
        storage: &mut Storage,
        ctx: &mut TxContext
    )
    :return:
    """
    genesis_proposal = load.genesis_proposal_package()
    governance = load.governance_package()
    lending_core = load.lending_core_package()
    oracle = load.oracle_package()
    # set apt as isolated asset
    is_isolated_asset = dola_pool_id == 5
    borrowable_in_isolation = dola_pool_id in [1, 2]
    genesis_proposal.genesis_proposal.vote_register_new_reserve(
        governance.governance_v1.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        clock(),
        dola_pool_id,
        is_isolated_asset,
        borrowable_in_isolation,
        0,
        int(0.1 * RAY),
        0,
        int(0.8 * RAY),
        int(1.1 * RAY),
        int(0.02 * RAY),
        int(0.07 * RAY),
        int(3 * RAY),
        int(0.45 * RAY),
        lending_core.storage.Storage[-1]
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
    return f"{sui_project.TestCoins[-1]}::coins::USDT"


def usdc():
    return f"{sui_project.TestCoins[-1]}::coins::USDC"


def dai():
    return f"{sui_project.TestCoins[-1]}::coins::DAI"


def matic():
    return f"{sui_project.TestCoins[-1]}::coins::MATIC"


def apt():
    return f"{sui_project.TestCoins[-1]}::coins::APT"


def eth():
    return f"{sui_project.TestCoins[-1]}::coins::ETH"


def btc():
    return f"{sui_project.TestCoins[-1]}::coins::BTC"


def bnb():
    return f"{sui_project.TestCoins[-1]}::coins::BNB"


def sui():
    return "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"


def clock():
    return "0x0000000000000000000000000000000000000000000000000000000000000006"


def coin(coin_type):
    return f"0x2::coin::Coin<{coin_type}>"


def balance(coin_type):
    return f"0x2::balance::Supply<{coin_type}>"


def pool(coin_type):
    return f"{sui_project.OmniPool[-1]}::dola_pool::Pool<{coin_type}>"


def proposal():
    return f"{sui_project.Governance[-1]}::governance_v1::Proposal<{sui_project.GenesisProposal[-1]}::genesis_proposal::Certificate>"


def bridge_pool_read_vaa(index=0):
    omnipool = load.omnipool_package()
    result = omnipool.wormhole_adapter_pool.read_vaa.simulate(
        omnipool.wormhole_adapter_pool.PoolState[-1], index
    )["events"][-1]["moveEvent"]["fields"]
    return "0x" + bytes(result["vaa"]).hex(), result["nonce"]


def bridge_core_read_vaa(index=0):
    wormhole_adapter_core = load.wormhole_adapter_core_package()
    result = wormhole_adapter_core.wormhole_adapter_core.read_vaa.simulate(
        wormhole_adapter_core.wormhole_adapter_core.CoreState[-1], index
    )["events"][0]["parsedJson"]
    return result["vaa"], result["nonce"]


def lending_portal_contract_id():
    # dola_portal = load.dola_portal_package()
    # lending_portal_info = dola_portal.get_object_with_super_detail(
    #     dola_portal.lending.LendingPortal[-1]
    # )
    #
    # return int(lending_portal_info['dola_contract']['dola_contract'])
    return 1


def query_relay_event(limit=1):
    dola_portal = load.dola_portal_package()
    return dola_portal.query_events(
        {"MoveEvent": f"{dola_portal.package_id}::lending::RelayEvent"}, limit=limit)['data']


def main():
    # 1. init omnipool
    init_wormhole_adapter_pool()

    create_pool(btc())
    create_pool(usdt())
    create_pool(usdc())
    create_pool(sui())

    # 2. init oracle
    register_token_price(0, 2300000, 2)
    register_token_price(1, 100, 2)
    register_token_price(2, 100, 2)
    register_token_price(3, 160000, 2)
    register_token_price(4, 78, 2)
    register_token_price(5, 1830, 2)
    register_token_price(6, 28500, 2)
    register_token_price(7, 100, 2)

    # 3. activate governance
    active_governance_v1()

    # 4. init wormhole adapter core
    create_proposal()
    vote_init_wormhole_adapter_core()

    # 5. init pool manager
    create_proposal()
    vote_register_new_pool(0, b"BTC", btc())

    create_proposal()
    vote_register_new_pool(1, b"USDT", usdt())

    create_proposal()
    vote_register_new_pool(2, b"USDC", usdc())

    create_proposal()
    vote_register_new_pool(7, b"SUI", sui())

    # 6. init system core
    create_proposal()
    vote_init_system_core()

    # 7. init lending_core
    create_proposal()
    vote_init_lending_core()

    # 8. init dola portal
    create_proposal()

    vote_init_dola_portal()

    # set sui's dola portal as pool spender
    create_proposal()
    lending_contract_id = lending_portal_contract_id()
    vote_remote_register_spender(0, lending_contract_id)
    (vaa, _) = bridge_core_read_vaa()
    register_spender(vaa)

    # 9. register evm chain group
    create_proposal()

    vote_init_chain_group_id(2, [4, 5, 7])

    # 10. register reserves

    create_proposal()

    vote_register_new_reserve(0)

    create_proposal()

    vote_register_new_reserve(1)

    create_proposal()

    vote_register_new_reserve(2)

    create_proposal()

    vote_register_new_reserve(3)

    create_proposal()

    vote_register_new_reserve(4)

    create_proposal()

    vote_register_new_reserve(5)

    create_proposal()

    vote_register_new_reserve(6)

    create_proposal()

    vote_register_new_reserve(7)


if __name__ == '__main__':
    main()
