
from brownie import LendingPortal, BridgePool
from scripts.init import usdt, btc


def portal_supply(pool, amount):
    """
    function supply(address pool, uint256 amount)

    :param amount:
    :param coin_type:
    :return: payload
    """

    LendingPortal[-1].supply(
        pool,
        int(amount)
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

    LendingPortal[-1].withdraw(
        pool,
        str(receiver),
        dst_chain,
        int(amount)
    )


def pool_withdraw(vaa):
    """
    function receiveWithdraw(bytes memory vaa)

    :param coin_type:
    :param vaa:
    :return:
    """
    BridgePool[-1].receive_withdraw(vaa)


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

    LendingPortal[-1].borrow(
        pool,
        str(receiver),
        dst_chain,
        int(amount)
    )


def portal_repay(pool, amount):
    """
    function repay(address pool, uint256 amount)

    :return:
    """

    LendingPortal[-1].repay(
        pool,
        int(amount)
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

    LendingPortal[-1].liquidate(
        str(receiver),
        dst_chain,
        debt_pool,
        int(amount),
        collateral_pool,
        0
    )


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
    monitor_supply()
