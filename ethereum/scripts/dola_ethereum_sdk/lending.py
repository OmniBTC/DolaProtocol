from dola_ethereum_sdk import get_account, DOLA_CONFIG, set_ethereum_network
from brownie import Contract
from dola_ethereum_sdk.init import btc_pool, get_pool_token, usdt_pool
from dola_ethereum_sdk.load import lending_portal_package, wormhole_bridge_package


def portal_supply(pool, amount):
    """
    function supply(address pool, uint256 amount)

    :param amount:
    :param coin_type:
    :return: payload
    """
    account = get_account()
    lending_portal = lending_portal_package()
    token = Contract.from_abi("ERC20", get_pool_token(
        pool), DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
    token.approve(pool, amount, {'from': account})
    lending_portal.supply(
        pool,
        int(amount),
        {'from': account}
    )


def portal_withdraw(pool, amount, dst_chain=1, receiver=None):
    """
    function withdraw(
        address pool,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    )
    :return:
    """
    account = get_account()
    lending_portal = lending_portal_package()
    lending_portal.withdraw(
        pool,
        str(receiver),
        dst_chain,
        int(amount),
        {'from': account}
    )


def pool_withdraw(vaa):
    """
    function receiveWithdraw(bytes memory vaa)

    :param coin_type:
    :param vaa:
    :return:
    """
    account = get_account()
    bridge_pool = wormhole_bridge_package()
    bridge_pool.receive_withdraw(vaa, {'from': account})


def portal_borrow(pool, amount, dst_chain=1, receiver=None):
    """
    function borrow(
        address pool,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    )
    :return:
    """
    account = get_account()
    lending_portal = lending_portal_package()
    lending_portal.borrow(
        pool,
        str(receiver),
        dst_chain,
        int(amount),
        {'from': account}
    )


def portal_repay(pool, amount):
    """
    function repay(address pool, uint256 amount)

    :return:
    """
    account = get_account()
    lending_portal = lending_portal_package()

    token = Contract.from_abi("ERC20", get_pool_token(
        pool), DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
    token.approve(pool, amount, {'from': account})
    lending_portal.repay(
        pool,
        int(amount),
        {'from': account}
    )


def portal_liquidate(debt_pool, collateral_pool, amount, dst_chain=1, receiver=None):
    """
    function liquidate(
        bytes memory receiver,
        uint16 dstChainId,
        address debtPool,
        uint256 amount,
        address collateralPool,
        uint64 liquidateUserId
    )
    :return:
    """
    account = get_account()
    lending_portal = lending_portal_package()

    token = Contract.from_abi("ERC20", get_pool_token(
        debt_pool), DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
    token.approve(debt_pool, amount, {'from': account})
    lending_portal.liquidate(
        str(receiver),
        dst_chain,
        debt_pool,
        int(amount),
        collateral_pool,
        0,
        {'from': account}
    )


def monitor_supply(pool, amount=1):
    print(portal_supply(pool, amount * 1e18))


def monitor_withdraw(pool, dst_chain=4, receiver=None):
    print(portal_withdraw(pool, 1e8, dst_chain, receiver))


def monitor_borrow(pool, amount=1, dst_chain=4, receiver=None):
    print(portal_borrow(pool, amount * 1e8, dst_chain, receiver))


def monitor_repay(pool, amount=1e18):
    print(portal_repay(pool, amount))


def monitor_liquidate(dst_chain=4, receiver=None):
    print(portal_liquidate(usdt_pool(), btc_pool(), 1e18, dst_chain, receiver))


def main():
    monitor_borrow(usdt_pool(), receiver=get_account().address)


if __name__ == "__main__":
    set_ethereum_network("bsc-test")
    main()
