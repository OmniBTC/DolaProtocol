import time

from sui_brownie import CacheObject, ObjectType

from dola_sui_sdk import load

# 1e27
RAY = 1000000000000000000000000000


def create_pool(coin_type):
    omnipool = load.omnipool_package()
    omnipool.dola_pool.create_pool(8, ty_args=[coin_type])


def register_token_price(dola_pool_id, price, decimal):
    """
    public entry fun register_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        timestamp: u64,
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
        int(time.time()),
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
        user_manager.user_manager.UserManagerInfo[-1],
        group_id,
        chain_ids
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
        pool_weight: u256,
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
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
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        is_isolated_asset: bool,
        borrowable_in_isolation: bool,
        treasury: u64,
        treasury_factor: u256,
        borrow_cap_ceiling: u128,
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
        CacheObject[ObjectType.from_type(proposal())]["Shared"][-1],
        oracle.oracle.PriceOracle[-1],
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
        ty_args=[coin_type]
    )


def force_claim_test_coin(coin_type, amount):
    test_coins = load.test_coins_package()
    test_coins.faucet.force_claim(
        test_coins.faucet.Faucet[-1],
        int(amount),
        ty_args=[coin_type]
    )


def add_test_coins_admin(address):
    test_coins = load.test_coins_package()
    test_coins.faucet.add_admin(
        test_coins.faucet.Faucet[-1],
        address,
    )


def usdt():
    return f"{CacheObject.TestCoins[-1]}::coins::USDT"


def usdc():
    return f"{CacheObject.TestCoins[-1]}::coins::USDC"


def dai():
    return f"{CacheObject.TestCoins[-1]}::coins::DAI"


def matic():
    return f"{CacheObject.TestCoins[-1]}::coins::MATIC"


def apt():
    return f"{CacheObject.TestCoins[-1]}::coins::APT"


def eth():
    return f"{CacheObject.TestCoins[-1]}::coins::ETH"


def btc():
    return f"{CacheObject.TestCoins[-1]}::coins::BTC"


def bnb():
    return f"{CacheObject.TestCoins[-1]}::coins::BNB"


def sui():
    return "0x2::sui::SUI"


def coin(coin_type):
    return f"0x2::coin::Coin<{coin_type}>"


def balance(coin_type):
    return f"0x2::balance::Supply<{coin_type}>"


def pool(coin_type):
    return f"{CacheObject.OmniPool[-1]}::dola_pool::Pool<{coin_type}>"


def proposal():
    return f"{CacheObject.Governance[-1]}::governance_v1::Proposal<{CacheObject.GenesisProposal[-1]}::genesis_proposal::Certificate>"


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
    )["events"][-1]["moveEvent"]["fields"]
    return "0x" + bytes(result["vaa"]).hex(), result["nonce"]


def main():
    # 1. init omnipool
    create_pool(btc())
    create_pool(usdt())
    create_pool(usdc())
    create_pool("0x0000000000000000000000000000000000000002::sui::SUI")

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
    vote_register_new_pool(
        7, b"SUI", "0x0000000000000000000000000000000000000002::sui::SUI")

    # 6. init lending_core
    create_proposal()
    vote_init_lending_core()

    # 7. init system core
    create_proposal()
    vote_init_system_core()

    # 8. init dola portal
    create_proposal()

    vote_init_dola_portal()

    # 9. register evm chain group
    create_proposal()

    vote_init_chain_group_id(2, [4, 5, 1422])

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
