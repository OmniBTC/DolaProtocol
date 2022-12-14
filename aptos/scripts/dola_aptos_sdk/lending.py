import base64

from dola_aptos_sdk import load

from dola_aptos_sdk.init import btc, usdt, bridge_pool_read_vaa

U64_MAX = 18446744073709551615


def claim_test_coin(coin_type):
    test_coins = load.test_coins_package()
    test_coins.coins.claim(
        ty_args=[coin_type]
    )


def portal_supply(coin_type, amount):
    """
    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
    )

    :param amount:
    :param coin_type:
    :return: payload
    """
    lending_portal = load.lending_portal_package()

    lending_portal.lending.supply(
        int(amount),
        ty_args=[coin_type]
    )
    return bridge_pool_read_vaa()


def portal_withdraw(coin_type, amount, dst_chain=1, receiver=None):
    """
    public entry fun withdraw<CoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        amount: u64,
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    account_address = lending_portal.account.account_address
    if receiver is None:
        assert dst_chain == 1
        receiver = account_address

    _result = lending_portal.lending.withdraw(
        str(receiver),
        dst_chain,
        int(amount),
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
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole_bridge.bridge_pool.receive_withdraw(
        vaa,
        ty_args=[coin_type]
    )


def portal_borrow(coin_type, amount, dst_chain=1, receiver=None):
    """
    public entry fun borrow<CoinType>(
        sender: &signer,
        receiver: vector<u8>,
        dst_chain: u64,
        amount: u64,
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    account_address = lending_portal.account.account_address
    if receiver is None:
        assert dst_chain == 1
        receiver = account_address

    _result = lending_portal.lending.borrow(
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
    lending_portal = load.lending_portal_package()

    _result = lending_portal.lending.repay(
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
    lending_portal = load.lending_portal_package()
    account_address = lending_portal.account.account_address
    if receiver is None:
        assert dst_chain == 1
        receiver = account_address

    _result = lending_portal.lending.liquidate(
        str(receiver),
        dst_chain,
        int(amount),
        ty_args=[debt_coin_type, collateral_coin_type]
    )
    return bridge_pool_read_vaa()


def monitor_supply(coin):
    print(portal_supply(coin, 1e8))


def monitor_withdraw(coin, dst_chain=1, receiver=None):
    print(portal_withdraw(coin, 1e7, dst_chain, receiver))


def monitor_borrow(coin, amount=1e8, dst_chain=1, receiver=None):
    print(portal_borrow(coin, amount, dst_chain, receiver))


def monitor_repay(coin, amount=1e8):
    print(portal_repay(coin, amount))


def monitor_liquidate(dst_chain=1, receiver=None):
    print(portal_liquidate(usdt(), btc(), 1e8, dst_chain, receiver))


if __name__ == "__main__":
    # claim_test_coin(usdt())
    # monitor_supply(usdt())
    # monitor_withdraw(btc())
    # monitor_borrow(usdt(), 100)
    monitor_repay(usdt(), 100)
