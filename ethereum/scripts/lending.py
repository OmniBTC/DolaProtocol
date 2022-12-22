
from brownie import LendingPortal, BridgePool, ERC20, Contract
from scripts.init import btc_pool, get_account, get_pool_token, usdt, btc, usdt_pool


def portal_supply(pool, amount):
    """
    function supply(address pool, uint256 amount)

    :param amount:
    :param coin_type:
    :return: payload
    """
    account = get_account()

    token = Contract.from_abi("ERC20", get_pool_token(pool), ERC20.abi)
    token.approve(pool, amount, {'from': account})
    LendingPortal[-1].supply(
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
    LendingPortal[-1].withdraw(
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
    BridgePool[-1].receive_withdraw(vaa, {'from': account})


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
    LendingPortal[-1].borrow(
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

    token = Contract.from_abi("ERC20", get_pool_token(pool), ERC20.abi)
    token.approve(pool, amount, {'from': account})
    LendingPortal[-1].repay(
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

    token = Contract.from_abi("ERC20", get_pool_token(debt_pool), ERC20.abi)
    token.approve(debt_pool, amount, {'from': account})
    LendingPortal[-1].liquidate(
        str(receiver),
        dst_chain,
        debt_pool,
        int(amount),
        collateral_pool,
        0,
        {'from': account}
    )


def monitor_supply(pool):
    print(portal_supply(pool, 1e18))


def monitor_withdraw(pool, dst_chain=1, receiver=None):
    print(portal_withdraw(pool, 1e17, dst_chain, receiver))


def monitor_borrow(pool, amount=1e18, dst_chain=1, receiver=None):
    print(portal_borrow(pool, amount, dst_chain, receiver))


def monitor_repay(pool, amount=1e18):
    print(portal_repay(pool, amount))


def monitor_liquidate(dst_chain=1, receiver=None):
    print(portal_liquidate(usdt_pool(), btc_pool(), 1e18, dst_chain, receiver))


def main():
    monitor_supply(usdt_pool())
