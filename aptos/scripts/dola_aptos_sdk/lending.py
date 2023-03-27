from dola_aptos_sdk import load
from dola_aptos_sdk.init import btc, usdt, bridge_pool_read_vaa

U64_MAX = 18446744073709551615


def claim_test_coin(coin_type):
    test_coins = load.test_coins_package()
    test_coins.coins.claim(
        ty_args=[coin_type]
    )


def portal_supply(coin_type, amount, relay_fee=0):
    """
    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
        relay_fee: u64
    )

    :param relay_fee:
    :param amount:
    :param coin_type:
    :return: payload
    """
    dola_portal = load.dola_portal_package()

    dola_portal.lending.supply(
        int(amount),
        int(relay_fee),
        ty_args=[coin_type]
    )
    return bridge_pool_read_vaa()


def portal_withdraw(coin_type, amount, relay_fee=0, dst_chain=1, receiver=None):
    """
    public entry fun withdraw_local<CoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        amount: u64,
        relay_fee: u64
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        assert dst_chain == 1
        receiver = account_address

    _result = dola_portal.lending.withdraw_local(
        str(receiver),
        dst_chain,
        int(amount),
        int(relay_fee),
        ty_args=[coin_type]
    )
    return bridge_pool_read_vaa()


def pool_withdraw(vaa, coin_type):
    """
    public entry fun receive_withdraw<CoinType>(
        vaa: vector<u8>,
    )
    :param coin_type:
    :param vaa:
    :return:
    """
    omnipool = load.omnipool_package()
    omnipool.wormhole_adapter_pool.receive_withdraw(
        vaa,
        ty_args=[coin_type]
    )


def portal_borrow(coin_type, amount, dst_chain=1, receiver=None):
    """
    public entry fun borrow_local<CoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        amount: u64,
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        assert dst_chain == 1
        receiver = account_address

    _result = dola_portal.lending.borrow_local(
        str(receiver),
        dst_chain,
        int(amount),
        ty_args=[coin_type]
    )
    return bridge_pool_read_vaa()


def portal_repay(coin_type, amount):
    """
    public entry fun repay<CoinType>(
        sender: &signer,
        repay_coin: u64,
    )
    :return:
    """
    dola_portal = load.dola_portal_package()

    _result = dola_portal.lending.repay(
        int(amount),
        ty_args=[coin_type]
    )
    return bridge_pool_read_vaa()


def portal_liquidate(debt_coin_type, collateral_coin_type, amount, dst_chain=1, receiver=None):
    """
    public entry fun liquidate<DebtCoinType, CollateralCoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        debt_coin: u64,
        // punished person
        liquidate_user_id: u64,
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    account_address = dola_portal.account.account_address
    if receiver is None:
        assert dst_chain == 1
        receiver = account_address

    _result = dola_portal.lending.liquidate(
        str(receiver),
        dst_chain,
        int(amount),
        ty_args=[debt_coin_type, collateral_coin_type]
    )
    return bridge_pool_read_vaa()


def portal_as_collateral(dola_pool_ids=None):
    """
    public entry fun as_collateral(
        sender: &signer,
        dola_pool_ids: vector<u16>,
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    if dola_pool_ids is None:
        dola_pool_ids = []

    _result = dola_portal.lending.as_collateral(
        dola_pool_ids
    )
    return bridge_pool_read_vaa()


def portal_cancel_as_collateral(dola_pool_ids=None):
    """
    public entry fun cancel_as_collateral(
        sender: &signer,
        dola_pool_ids: vector<u16>,
    )
    :return:
    """
    dola_portal = load.dola_portal_package()
    if dola_pool_ids is None:
        dola_pool_ids = []

    _result = dola_portal.lending.cancel_as_collateral(
        dola_pool_ids
    )
    return bridge_pool_read_vaa()


def portal_binding(bind_address, dola_chain_id=5):
    """
    public entry fun binding(
        sender: &signer,
        dola_chain_id: u16,
        binded_address: vector<u8>,
    )
    :return:
    """
    dola_portal = load.dola_portal_package()

    _result = dola_portal.system.binding(
        dola_chain_id,
        bind_address
    )
    return bridge_pool_read_vaa()


def portal_unbinding(bind_address, dola_chain_id=5):
    """
    public entry fun unbinding(
        sender: &signer,
        dola_chain_id: u16,
        unbinded_address: vector<u8>
    )
    :return:
    """
    dola_portal = load.dola_portal_package()

    _result = dola_portal.system.unbinding(
        dola_chain_id,
        bind_address
    )
    return bridge_pool_read_vaa()


def monitor_supply(coin):
    print(portal_supply(coin, 1e8))


def monitor_withdraw(coin, relay_fee=0, dst_chain=1, receiver=None):
    print(portal_withdraw(coin, 1e7, relay_fee, dst_chain, receiver))


def monitor_borrow(coin, amount=1e8, dst_chain=1, receiver=None):
    print(portal_borrow(coin, amount, dst_chain, receiver))


def monitor_repay(coin, amount=1e8):
    print(portal_repay(coin, amount))


def monitor_liquidate(dst_chain=1, receiver=None):
    print(portal_liquidate(usdt(), btc(), 1e8, dst_chain, receiver))


if __name__ == "__main__":
    claim_test_coin(usdt())
    portal_supply(usdt(), 1e8, 0)
    # monitor_withdraw(usdt(), 10000)
    # monitor_borrow(usdt(), 100)
    # monitor_repay(usdt(), 100)
