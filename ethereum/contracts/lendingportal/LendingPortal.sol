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
    address public dolaDiamond;

    constructor(address diamond) {
        dolaDiamond = diamond;
    }

    function supply(address _token, uint256 _amount) external payable {
        uint8 decimal = IERC20(_token).decimals();
        bytes memory tokenName = bytes(IERC20(_token).name());
        bytes memory appPayload = LibLending.encodeAppPayload(
            SUPPLY,
            LibDecimals.fixAmountDecimals(_amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeFacet(dolaDiamond).sendDeposit{value: msg.value}(
            tokenName,
            _amount,
            APPID,
            appPayload
        );
    }

    // withdraw use 8 decimal
    function withdraw(
        bytes memory _tokenName,
        uint64 _amount,
        uint16 _dstChainId
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            WITHDRAW,
            _amount,
            abi.encodePacked(tx.origin),
            _dstChainId
        );
        IWormholeFacet(dolaDiamond).sendWithdraw{value: msg.value}(
            _tokenName,
            APPID,
            appPayload
        );
    }

    function borrow(
        bytes memory _tokenName,
        uint64 _amount,
        uint16 _dstChainId
    ) external payable {
        bytes memory appPayload = LibLending.encodeAppPayload(
            BORROW,
            _amount,
            abi.encodePacked(tx.origin),
            _dstChainId
        );
        IWormholeFacet(dolaDiamond).sendWithdraw{value: msg.value}(
            _tokenName,
            APPID,
            appPayload
        );
    }

    function repay(
        bytes memory _tokenName,
        address _token,
        uint256 _amount
    ) external payable {
        uint8 decimal = IERC20(_token).decimals();
        bytes memory appPayload = LibLending.encodeAppPayload(
            REPAY,
            LibDecimals.fixAmountDecimals(_amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeFacet(dolaDiamond).sendDeposit{value: msg.value}(
            _tokenName,
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
        bytes memory depositTokenName = bytes(IERC20(_depositToken).name());
        bytes memory withdrawTokenName = bytes(IERC20(_withdrawToken).name());
        bytes memory appPayload = LibLending.encodeAppPayload(
            LIQUIDATE,
            LibDecimals.fixAmountDecimals(_amount, decimal),
            abi.encodePacked(tx.origin),
            0
        );
        IWormholeFacet(dolaDiamond).sendDepositAndWithdraw(
            depositTokenName,
            _amount,
            _withdrawToken,
            _punished,
            withdrawTokenName,
            APPID,
            appPayload
        );
    }
}
