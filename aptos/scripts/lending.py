import base64
from pprint import pprint

import load

U64_MAX = 18446744073709551615


def usdt():
    return f"0x38e78c11434f91f2138ab82a8e737acab6995d01577177fb6d64f09297b60fb2::coins::USDT"


def btc():
    return f"0x38e78c11434f91f2138ab82a8e737acab6995d01577177fb6d64f09297b60fb2::coins::BTC"


def aptos():
    return "0x1::aptos_coin::AptosCoin"


def claim_test_coin(coin_type):
    test_coins = load.test_coins_package()
    test_coins.faucet.claim(
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
    wormhole_bridge = load.wormhole_bridge_package()

    lending_portal.lending.supply(
        amount,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def portal_withdraw(coin_type, amount):
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
    wormhole_bridge = load.wormhole_bridge_package()
    account_address = lending_portal.account.account_address
    dst_chain = 1

    result = lending_portal.lending.withdraw(
        str(account_address),
        dst_chain,
        amount,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


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
        list(base64.b64decode(vaa)),
        ty_args=[coin_type]
    )


def portal_borrow(coin_type, amount):
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
    wormhole_bridge = load.wormhole_bridge_package()
    wormhole = load.wormhole_package()
    account_address = lending_portal.account.account_address
    dst_chain = 1

    result = lending_portal.lending.borrow(
        str(account_address),
        dst_chain,
        amount,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def portal_repay(coin_type, amount):
    """
    public entry fun repay<CoinType>(
        sender: &signer,
        repay_coin: u64,
    )
    :return:
    """
    lending_portal = load.lending_portal_package()
    wormhole_bridge = load.wormhole_bridge_package()

    result = lending_portal.lending.repay(
        amount,
        ty_args=[coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def portal_liquidate(debt_coin_type, collateral_coin_type, amount):
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
    wormhole_bridge = load.wormhole_bridge_package()
    dst_chain = 1
    account_address = lending_portal.account.account_address

    result = lending_portal.lending.liquidate(
        str(account_address),
        dst_chain,
        amount,
        ty_args=[debt_coin_type, collateral_coin_type]
    )
    return wormhole_bridge.bridge_pool.read_vaa.simulate(
        wormhole_bridge.bridge_pool.PoolState[-1], 0
    )["events"][-1]["moveEvent"]["fields"]["vaa"]


def monitor_supply(coin):
    claim_test_coin(coin)
    vaa = portal_supply(coin)


def monitor_withdraw():
    to_core_vaa = portal_withdraw(btc(), 1e8)


def monitor_borrow(coin, amount=1):
    to_core_vaa = portal_borrow(coin, amount * 1e8)


def monitor_repay():
    vaa = portal_repay(usdt())


def monitor_liquidate():
    vaa = portal_liquidate(usdt(), btc())


if __name__ == "__main__":
    monitor_supply()
