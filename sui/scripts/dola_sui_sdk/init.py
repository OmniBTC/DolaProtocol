import base64
import time

from sui_brownie import CacheObject

from . import load

RAY = 100000000


def init_bridge_core():
    '''
    public entry fun initialize_wormhole(wormhole_state: &mut WormholeState, ctx: &mut TxContext)
    :return:
    '''
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    wormhole_bridge.bridge_core.initialize_wormhole(wormhole.state.State[-1])


def init_bridge_pool():
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    wormhole_bridge.bridge_pool.initialize_wormhole(wormhole.state.State[-1])


def create_pool(coin_type):
    omnipool = load.omnipool_package()
    omnipool.pool.create_pool(8, ty_args=[coin_type])


def add_governance_member(member):
    governance = load.governance_package()
    governance.governance.add_member(governance.governance.GovernanceCap[-1], governance.governance.Governance[-1],
                                     member)


def register_pool_manager_admin_cap():
    pool_manager = load.pool_manager_package()
    governance = load.governance_package()
    result = pool_manager.pool_manager.register_admin_cap(
        pool_manager.pool_manager.PoolManagerInfo[-1],
        governance.governance.GovernanceExternalCap[-1]
    )
    return result['events'][-1]['moveEvent']['fields']['hash']


def register_app_manager_cap():
    app_manager = load.app_manager_package()
    governance = load.governance_package()
    result = app_manager.app_manager.register_admin_cap(
        app_manager.app_manager.TotalAppInfo[-1],
        governance.governance.GovernanceExternalCap[-1]
    )
    return result['events'][-1]['moveEvent']['fields']['hash']


def register_lending_storage_admin_cap():
    lending = load.lending_package()
    governance = load.governance_package()
    result = lending.storage.register_admin_cap(
        lending.storage.Storage[-1],
        governance.governance.GovernanceExternalCap[-1]
    )
    return result['events'][-1]['moveEvent']['fields']['hash']


def register_token_price(dola_pool_id, price, decimal):
    '''
    public entry fun register_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        timestamp: u64,
        dola_pool_id: u16,
        token_price: u64,
        price_decimal: u8
    )
    :return:
    '''
    oracle = load.oracle_package()

    oracle.oracle.register_token_price(
        oracle.oracle.OracleCap[-1],
        oracle.oracle.PriceOracle[-1],
        int(time.time()),
        dola_pool_id,
        price,
        decimal
    )


def create_vote_external_cap(hash):
    governance = load.governance_package()
    governance.governance.create_vote_external_cap(governance.governance.Governance[-1], list(base64.b64decode(hash)))


def init_user_manager_cap_for_bridge():
    '''
    public entry fun init_user_manager_cap_for_bridge(core_state: &mut CoreState)
    :return:
    '''
    example_proposal = load.example_proposal_package()
    wormhole_bridge = load.wormhole_bridge_package()

    example_proposal.init_user_manager.init_user_manager_cap_for_bridge(wormhole_bridge.bridge_core.CoreState[-1])


def vote_pool_manager_cap_proposal():
    '''
    Ensure init bridge_core to create CoreState

    public entry fun vote_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        core_state: &mut CoreState,
        ctx: &mut TxContext
    )
    :return:
    '''
    example_proposal = load.example_proposal_package()
    governance = load.governance_package()
    wormhole_bridge = load.wormhole_bridge_package()
    return example_proposal.init_pool_manager.vote_pool_manager_cap_proposal(governance.governance.Governance[-1],
                                                                             governance.governance.GovernanceExternalCap[
                                                                                 -1],
                                                                             governance.governance.VoteExternalCap[-1],
                                                                             wormhole_bridge.bridge_core.CoreState[-1])


def vote_register_new_pool_proposal(pool_id, pool_name, coin_type):
    '''
    public entry fun vote_register_new_pool_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        pool_manager_info: &mut PoolManagerInfo,
        pool_dola_chain_id: u16,
        pool_dola_address: vector<u8>,
        dola_pool_name: vector<u8>,
        dola_pool_id: u16,
        ctx: &mut TxContext
    )
    :return:
    '''
    if isinstance(coin_type, str):
        coin_type = list(bytes(coin_type, "ascii"))
    example_proposal = load.example_proposal_package()
    governance = load.governance_package()
    pool_manager = load.pool_manager_package()
    example_proposal.init_pool_manager.vote_register_new_pool_proposal(governance.governance.Governance[-1],
                                                                       governance.governance.GovernanceExternalCap[-1],
                                                                       governance.governance.VoteExternalCap[-1],
                                                                       pool_manager.pool_manager.PoolManagerInfo[-1],
                                                                       coin_type,
                                                                       0,
                                                                       list(pool_name),
                                                                       pool_id
                                                                       )


def vote_storage_cap_proposal():
    '''
    public entry fun vote_storage_cap_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        wormhole_adapater: &mut WormholeAdapater,
        ctx: &mut TxContext
    )
    :return:
    '''
    example_proposal = load.example_proposal_package()
    governance = load.governance_package()
    lending = load.lending_package()
    example_proposal.init_lending_storage.vote_storage_cap_proposal(governance.governance.Governance[-1],
                                                                    governance.governance.GovernanceExternalCap[-1],
                                                                    governance.governance.VoteExternalCap[-1],
                                                                    lending.wormhole_adapter.WormholeAdapater[-1])


def vote_app_cap_proposal():
    '''
    public entry fun vote_app_cap_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        storage: &mut Storage,
        total_app_info: &mut TotalAppInfo,
        ctx: &mut TxContext
    )
    :return:
    '''
    example_proposal = load.example_proposal_package()
    governance = load.governance_package()
    lending = load.lending_package()
    app_manager = load.app_manager_package()
    example_proposal.init_lending_storage.vote_app_cap_proposal(
        governance.governance.Governance[-1],
        governance.governance.GovernanceExternalCap[-1],
        governance.governance.VoteExternalCap[-1],
        lending.storage.Storage[-1],
        app_manager.app_manager.TotalAppInfo[-1]
    )


def vote_register_new_reserve_proposal(dola_pool_id):
    '''
    public entry fun vote_register_new_reserve_proposal(
        gov: &mut Governance,
        governance_external_cap: &mut GovernanceExternalCap,
        vote: &mut VoteExternalCap,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
        treasury: u64,
        treasury_factor: u64,
        collateral_coefficient: u64,
        borrow_coefficient: u64,
        base_borrow_rate: u64,
        borrow_rate_slope1: u64,
        borrow_rate_slope2: u64,
        optimal_utilization: u64,
        storage: &mut Storage,
        ctx: &mut TxContext
    )
    :return:
    '''
    example_proposal = load.example_proposal_package()
    governance = load.governance_package()
    lending = load.lending_package()
    oracle = load.oracle_package()
    example_proposal.init_lending_storage.vote_register_new_reserve_proposal(
        governance.governance.Governance[-1],
        governance.governance.GovernanceExternalCap[-1],
        governance.governance.VoteExternalCap[-1],
        oracle.oracle.PriceOracle[-1],
        dola_pool_id,
        0,
        int(0.01 * RAY),
        int(0.01 * RAY),
        int(0.01 * RAY),
        int(0.02 * RAY),
        int(0.07 * RAY),
        int(3 * RAY),
        int(0.45 * RAY),
        lending.storage.Storage[-1]
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


def btc():
    return f"{CacheObject.TestCoins[-1]}::coins::BTC"


def sui():
    return "0x2::sui::SUI"


def coin(coin_type):
    return f"0x2::coin::Coin<{coin_type}>"


def balance(coin_type):
    return f"0x2::balance::Supply<{coin_type}>"


def pool(coin_type):
    return f"{CacheObject.OmniPool[-1]}::pool::Pool<{coin_type}>"


def main():
    # 1. init bridge
    init_bridge_core()
    init_bridge_pool()

    # 2. init omnipool
    create_pool(usdt())
    create_pool(btc())
    claim_test_coin(btc())
    force_claim_test_coin(usdt(), 100000)

    # 3. init oracle
    register_token_price(0, 2000000, 2)
    register_token_price(1, 100, 2)

    # 4. init user manager
    init_user_manager_cap_for_bridge()

    # 5. init pool manager
    hash = register_pool_manager_admin_cap()
    create_vote_external_cap(hash)
    vote_pool_manager_cap_proposal()

    create_vote_external_cap(hash)
    vote_register_new_pool_proposal(0, b"BTC", btc())

    create_vote_external_cap(hash)
    vote_register_new_pool_proposal(1, b"USDT", usdt())
    # 6. init lending storage

    hash = register_app_manager_cap()
    create_vote_external_cap(hash)
    vote_app_cap_proposal()
    # register storage cap
    hash = register_lending_storage_admin_cap()
    create_vote_external_cap(hash)

    vote_storage_cap_proposal()
    # register reserves
    create_vote_external_cap(hash)

    vote_register_new_reserve_proposal(0)

    create_vote_external_cap(hash)

    vote_register_new_reserve_proposal(1)


if __name__ == '__main__':
    main()
