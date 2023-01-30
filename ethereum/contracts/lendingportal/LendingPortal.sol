// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IWormholeBridge.sol";
import "../../interfaces/IOmniPool.sol";
import "../libraries//LibLending.sol";
import "../libraries//LibDecimals.sol";
import "../libraries//LibDolaTypes.sol";

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

    function tokenDecimals(address token) internal view returns (uint8) {
        uint8 decimal = 18;
        if (token != address(0)) {
            decimal = IERC20(token).decimals();
        }
        return decimal;
    }

    function supply(address token, uint256 amount) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            SUPPLY,
            LibDecimals.fixAmountDecimals(amount, tokenDecimals(token)),
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value: msg.value}(
            token,
            amount,
            APPID,
            appPayload
        );
    }

    // withdraw use 8 decimal
    function withdraw(
        address token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            WITHDRAW,
            amount,
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value: msg.value}(
            token,
            APPID,
            appPayload
        );
    }

    function borrow(
        address token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            BORROW,
            amount,
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value: msg.value}(
            token,
            APPID,
            appPayload
        );
    }

    function repay(address token, uint256 amount) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            REPAY,
            LibDecimals.fixAmountDecimals(amount, tokenDecimals(token)),
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value: msg.value}(
            token,
            amount,
            APPID,
            appPayload
        );
    }

    function liquidate(
        bytes memory receiver,
        uint16 dstChainId,
        address debtToken,
        uint256 amount,
        address collateralToken,
        uint64 liquidateUserId
    ) external {
        bytes memory appPayload = LibLending.encodeAppPayload(
            LIQUIDATE,
            LibDecimals.fixAmountDecimals(amount, tokenDecimals(debtToken)),
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            liquidateUserId
        );
        IWormholeBridge(bridgePool).sendDepositAndWithdraw(
            debtToken,
            amount,
            collateralToken,
            APPID,
            appPayload
        );
    }
}
