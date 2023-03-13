from brownie import Contract

import dola_ethereum_sdk.load as load
from dola_ethereum_sdk import get_account, DOLA_CONFIG, set_ethereum_network
from dola_ethereum_sdk.init import usdt, btc


def portal_as_collateral(pool_ids=None):
    """
    function as_collateral(uint16[] memory dolaPoolIds) external payable
    :return:
    """
    account = get_account()
    lending_portal = load.lending_portal_package()
    if pool_ids is None:
        pool_ids = []

    lending_portal.as_collateral(
        pool_ids,
        {'from': account}
    )


def portal_cancel_as_collateral(pool_ids=None):
    """
    function cancel_as_collateral(uint16[] memory dolaPoolIds)
    :return:
    """
    account = get_account()
    lending_portal = load.lending_portal_package()
    if pool_ids is None:
        pool_ids = []

    lending_portal.cancel_as_collateral(
        pool_ids,
        {'from': account}
    )


def portal_supply(token, amount):
    """
    function supply(address token, uint256 amount)

    :param token:
    :param amount:
    :return: payload
    """
    account = get_account()
    lending_portal = load.lending_portal_package()
    token = Contract.from_abi("MockToken", token, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].abi)
    token.mint(account.address, amount, {'from': account})
    token.approve(lending_portal.address, amount, {'from': account})
    lending_portal.supply(
        token,
        int(amount),
        {'from': account}
    )


def portal_supply_eth(amount):
    """
        function supply(address token, uint256 amount)

        :param token:
        :param amount:
        :return: payload
        """
    account = get_account()
    lending_portal = load.lending_portal_package()
    eth = "0x0000000000000000000000000000000000000000"
    lending_portal.supply(
        eth,
        int(amount),
        {'from': account, 'value': amount}
    )


def portal_withdraw(token, amount, dst_chain=1, receiver=None):
    """
    function withdraw(
        bytes memory token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    )
    :return:
    """
    account = get_account()
    lending_portal = load.lending_portal_package()
    lending_portal.withdraw(
        str(token),
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
    wormhole_adapter_pool = load.wormhole_adapter_pool_package()
    wormhole_adapter_pool.receive_withdraw(vaa, {'from': account})


def portal_borrow(token, amount, dst_chain=1, receiver=None):
    """
    function borrow(
        bytes memory token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    )
    :return:
    """
    account = get_account()
    lending_portal = load.lending_portal_package()
    lending_portal.borrow(
        str(token),
        str(receiver),
        dst_chain,
        int(amount),
        {'from': account}
    )


def portal_repay(token, amount):
    """
    function repay(address token, uint256 amount)

    :return:
    """
    account = get_account()
    lending_portal = load.lending_portal_package()

    token = Contract.from_abi("ERC20", token, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
    token.approve(lending_portal.address, amount, {'from': account})
    lending_portal.repay(
        token,
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
    lending_portal = load.lending_portal_package()

    token = Contract.from_abi("ERC20", debt_pool, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
    token.approve(lending_portal.address, amount, {'from': account})
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
    print(portal_withdraw(pool, 1e16, dst_chain, receiver))


def monitor_borrow(pool, amount=1, dst_chain=4, receiver=None):
    print(portal_borrow(pool, amount * 1e8, dst_chain, receiver))


def monitor_repay(pool, amount=1):
    print(portal_repay(pool, amount * 1e18))


def monitor_liquidate(dst_chain=4, receiver=None):
    print(portal_liquidate(usdt(), btc(), 1e18, dst_chain, receiver))


def main():
    # monitor_supply(usdt(), 100000)
    # monitor_supply(usdc(), 100000)
    # portal_cancel_as_collateral([1, 2])
    monitor_withdraw("0x0000000000000000000000000000000000000000", 5, get_account().address)
    # monitor_borrow(usdt_pool(), 1000, receiver=get_account().address)
    # monitor_repay(usdt_pool())


if __name__ == "__main__":
    set_ethereum_network("polygon-test")
    main()
