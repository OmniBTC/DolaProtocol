// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IWormholeBridge.sol";
import "../../libraries/LibLending.sol";
import "../../libraries/LibDecimals.sol";

contract LendingPortal {
    uint8 public constant APPID = 0;
    uint8 private constant SUPPLY = 0;
    uint8 private constant WITHDRAW = 1;
    uint8 private constant BORROW = 2;
    uint8 private constant REPAY = 3;
    uint8 private constant LIQUIDATE = 4;
    address public dolaDiamond;

    constructor(address diamond) {
        dolaDiamond = diamond;
    }

    function supply(address token, uint256 amount) external payable {
        uint8 decimal = IERC20(token).decimals();
        bytes memory tokenName = bytes(IERC20(token).name());
        bytes memory appPayload = LibLending.encodeAppPayload(
            SUPPLY,
            LibDecimals.fixAmountDecimals(amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeBridge(dolaDiamond).sendDeposit{value: msg.value}(
            tokenName,
            amount,
            APPID,
            appPayload
        );
    }

    // withdraw use 8 decimal
    function withdraw(
        bytes memory tokenName,
        uint64 amount,
        uint16 dstChainId
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            WITHDRAW,
            amount,
            abi.encodePacked(tx.origin),
            dstChainId
        );
        IWormholeBridge(dolaDiamond).sendWithdraw{value: msg.value}(
            tokenName,
            APPID,
            appPayload
        );
    }

    function borrow(
        bytes memory tokenName,
        uint64 amount,
        uint16 dstChainId
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            BORROW,
            amount,
            abi.encodePacked(tx.origin),
            dstChainId
        );
        IWormholeBridge(dolaDiamond).sendWithdraw{value: msg.value}(
            tokenName,
            APPID,
            appPayload
        );
    }

    function repay(
        bytes memory tokenName,
        address token,
        uint256 amount
    ) external payable {
        uint8 decimal = IERC20(token).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            REPAY,
            LibDecimals.fixAmountDecimals(amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeBridge(dolaDiamond).sendDeposit{value: msg.value}(
            tokenName,
            amount,
            APPID,
            appPayload
        );
    }

    function liquidate(
        address depositToken,
        uint256 amount,
        address withdrawToken,
        address punished
    ) external {
        uint8 decimal = IERC20(depositToken).decimals();
        bytes memory depositTokenName = bytes(IERC20(depositToken).name());
        bytes memory withdrawTokenName = bytes(IERC20(withdrawToken).name());
        bytes memory appPayload = LibLending.encodeAppPayload(
            LIQUIDATE,
            LibDecimals.fixAmountDecimals(amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeBridge(dolaDiamond).sendDepositAndWithdraw(
            depositTokenName,
            amount,
            withdrawToken,
            punished,
            withdrawTokenName,
            APPID,
            appPayload
        );
    }
}
