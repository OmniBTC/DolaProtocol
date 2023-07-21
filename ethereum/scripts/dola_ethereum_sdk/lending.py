from brownie import Contract, network

import dola_ethereum_sdk.load as load
from dola_ethereum_sdk import get_account, DOLA_CONFIG, set_ethereum_network


def portal_binding(bind_address, dola_chain_id=5, fee=0):
    """
    function binding(uint16 bindDolaChainId, bytes memory bindAddress)
    :param fee:
    :param dola_chain_id:
    :param bind_address:
    :return:
    """
    account = get_account()
    system_portal = load.system_portal_package(network.show_active())
    system_portal.binding(
        dola_chain_id,
        bind_address,
        fee,
        {'from': account, 'value': fee}
    )


def portal_unbinding(unbind_address, dola_chain_id=5):
    """
    function unbinding(uint16 unbindDolaChainId, bytes memory unbindAddress)
    :return:
    """
    account = get_account()
    system_portal = load.system_portal_package(network.show_active())
    system_portal.unbinding(
        dola_chain_id,
        unbind_address,
        {'from': account}
    )


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
    lending_portal = load.lending_portal_package(network.show_active())
    if pool_ids is None:
        pool_ids = []

    lending_portal.cancel_as_collateral(
        pool_ids,
        {'from': account}
    )


def portal_supply(token, amount, relay_fee=0):
    """
    function supply(address token, uint256 amount)

    :param relay_fee:
    :param token:
    :param amount:
    :return: payload
    """
    account = get_account()

    lending_portal = load.lending_portal_package(network.show_active())
    if "test" in network.show_active():
        token = Contract.from_abi(
            "MockToken", token, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].abi)
        token.mint(account.address, amount, {'from': account})
    else:
        token = Contract.from_abi(
            "ERC20", token, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
    token.approve(lending_portal.address, amount, {'from': account})
    lending_portal.supply(
        token,
        int(amount),
        relay_fee,
        {'from': account, 'value': relay_fee}
    )


def portal_supply_eth(amount):
    """
        function supply(address token, uint256 amount)

        :param token:
        :param amount:
        :return: payload
        """
    account = get_account()
    lending_portal = load.lending_portal_package(network.show_active())
    eth = "0x0000000000000000000000000000000000000000"
    lending_portal.supply(
        eth,
        int(amount),
        {'from': account, 'value': amount}
    )


def portal_withdraw(token, amount, dst_chain=5, receiver=None, relay_fee=0):
    """
    function withdraw(
        bytes memory token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount,
        uint256 fee
    )
    :return:
    """
    account = get_account()
    if receiver is None:
        receiver = account.address

    lending_portal = load.lending_portal_package(network.show_active())
    lending_portal.withdraw(
        str(token),
        str(receiver),
        dst_chain,
        int(amount),
        int(relay_fee),
        {'from': account, 'value': relay_fee}
    )


def pool_withdraw(vaa):
    """
    function receiveWithdraw(bytes memory vaa)

    :param coin_type:
    :param vaa:
    :return:
    """
    account = get_account()
    wormhole_adapter_pool = load.wormhole_adapter_pool_package(
        network.show_active())
    wormhole_adapter_pool.receiveWithdraw(vaa, {'from': account})


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
    lending_portal = load.lending_portal_package(network.show_active())
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

    token = Contract.from_abi(
        "ERC20", token, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
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
    lending_portal = load.lending_portal_package(network.show_active())

    token = Contract.from_abi(
        "ERC20", debt_pool, DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)
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


def get_account_balance():
    account = get_account()
    return account.balance()


def main():
    portal_binding('0xa27e571EDd0724ee2245BeCe7DAf52d9c243400E', 6)
    # portal_supply(init.usdt()['address'], 1 * 1e6)
    # portal_cancel_as_collateral([1, 2])
    # portal_withdraw(usdt()['address'], 0.1 * 1e8, 23, relay_fee=int(1e14))
    # portal_binding(
    #     "0x29b710abd287961d02352a5e34ec5886c63aa5df87a209b2acbdd7c9282e6566", 0, fee=int(1e14))
    # monitor_borrow(usdt_pool(), 1000, receiver=get_account().address)
    # monitor_repay(usdt_pool())


if __name__ == "__main__":
    set_ethereum_network("avax-test")
    main()
