// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IWormholeBridge.sol";
import "../../interfaces/IOmniPool.sol";
import "../../libraries/LibLending.sol";
import "../../libraries/LibDecimals.sol";
import "../../libraries/LibDolaTypes.sol";

contract LendingPortal {
    uint8 public constant APPID = 0;
    uint8 private constant SUPPLY = 0;
    uint8 private constant WITHDRAW = 1;
    uint8 private constant BORROW = 2;
    uint8 private constant REPAY = 3;
    uint8 private constant LIQUIDATE = 4;
    address public bridgePool;
    uint16 public dolaChainId;

    constructor(address bridge, uint16 chainId) {
        bridgePool = bridge;
        dolaChainId = chainId;
    }

    function supply(address pool, uint256 amount) external payable {
        uint8 decimal = IOmniPool(pool).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            SUPPLY,
            LibDecimals.fixAmountDecimals(amount, decimal),
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value: msg.value}(
            pool,
            amount,
            APPID,
            appPayload
        );
    }

    // withdraw use 8 decimal
    function withdraw(
        address pool,
        uint64 amount,
        uint16 dstChainId
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            WITHDRAW,
            amount,
            LibDolaTypes.addressToDolaAddress(dstChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value: msg.value}(
            pool,
            APPID,
            appPayload
        );
    }

    function borrow(
        address pool,
        uint64 amount,
        uint16 dstChainId
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            BORROW,
            amount,
            LibDolaTypes.addressToDolaAddress(dstChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value: msg.value}(
            pool,
            APPID,
            appPayload
        );
    }

    function repay(address pool, uint256 amount) external payable {
        uint8 decimal = IOmniPool(pool).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            REPAY,
            LibDecimals.fixAmountDecimals(amount, decimal),
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value: msg.value}(
            pool,
            amount,
            APPID,
            appPayload
        );
    }

    function liquidate(
        address depositPool,
        uint256 amount,
        address withdrawPool,
        uint64 punished
    ) external {
        uint8 decimal = IOmniPool(depositPool).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            LIQUIDATE,
            LibDecimals.fixAmountDecimals(amount, decimal),
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            punished
        );
        IWormholeBridge(bridgePool).sendDepositAndWithdraw(
            depositPool,
            amount,
            withdrawPool,
            APPID,
            appPayload
        );
    }
}
