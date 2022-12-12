// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IWormholeFacet.sol";
import "../../libraries/LibLending.sol";
import "../../libraries/LibDecimals.sol";

contract LendingPortal {
    uint8 public constant APPID = 0;
    uint8 private constant SUPPLY = 0;
    uint8 private constant WITHDRAW = 1;
    uint8 private constant BORROW = 2;
    uint8 private constant REPAY = 3;
    uint8 private constant LIQUIDATE = 4;
    address public bridge;

    constructor(address _bridge) {
        bridge = _bridge;
    }

    function supply(address _token, uint256 _amount) external payable {
        uint8 decimal = IERC20(_token).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            SUPPLY,
            LibDecimals.fixAmountDecimals(_amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeFacet(bridge).sendDeposit{value: msg.value}(
            _amount,
            APPID,
            appPayload
        );
    }

    // withdraw use 8 decimal
    function withdraw(uint64 _amount, uint16 _dstChainId) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            WITHDRAW,
            _amount,
            abi.encodePacked(tx.origin),
            _dstChainId
        );
        IWormholeFacet(bridge).sendWithdraw{value: msg.value}(
            APPID,
            appPayload
        );
    }

    function borrow(uint64 _amount, uint16 _dstChainId) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            BORROW,
            _amount,
            abi.encodePacked(tx.origin),
            _dstChainId
        );
        IWormholeFacet(bridge).sendWithdraw{value: msg.value}(
            APPID,
            appPayload
        );
    }

    function repay(address _token, uint256 _amount) external payable {
        uint8 decimal = IERC20(_token).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            REPAY,
            LibDecimals.fixAmountDecimals(_amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeFacet(bridge).sendDeposit{value: msg.value}(
            _amount,
            APPID,
            appPayload
        );
    }

    function liquidate(
        address _depositToken,
        uint256 _amount,
        address _withdrawToken,
        address _punished
    ) external {
        uint8 decimal = IERC20(_depositToken).decimals();
        bytes memory withdrawTokenName = bytes(IERC20(_withdrawToken).symbol());
        bytes memory appPayload = LibLending.encodeAppPayload(
            LIQUIDATE,
            LibDecimals.fixAmountDecimals(_amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeFacet(bridge).sendDepositAndWithdraw(
            _amount,
            _withdrawToken,
            _punished,
            withdrawTokenName,
            APPID,
            appPayload
        );
    }
}
