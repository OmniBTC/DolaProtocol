// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IWormholeBridge.sol";
import "../../interfaces/IOmniPool.sol";
import "../libraries//LibLending.sol";
import "../libraries//LibDecimals.sol";
import "../libraries//LibDolaTypes.sol";

contract DolaPortal {
    uint8 public constant LENDING_APP_ID = 1;
    uint8 private constant SUPPLY = 0;
    uint8 private constant WITHDRAW = 1;
    uint8 private constant BORROW = 2;
    uint8 private constant REPAY = 3;
    uint8 private constant LIQUIDATE = 4;
    uint8 private constant BINDING = 5;
    uint8 private constant UNBINDING = 6;
    uint8 private constant AS_COLLATERAL = 7;
    uint8 private constant CANCEL_AS_COLLATERAL = 8;
    address public bridgePool;
    uint16 public dolaChainId;
    uint64 public dolaNonce;

    event ProtocolPortalEvent(
        uint64 nonce,
        address sender,
        uint16 sourceChainId,
        uint16 userChainId,
        bytes userAddress,
        uint8 callType
    );
    event LendingPortalEvent(
        uint64 nonce,
        address sender,
        bytes dolaPoolAddress,
        uint16 sourceChainId,
        uint16 dstChainId,
        bytes receiver,
        uint64 amount,
        uint8 callType
    );

    constructor(address bridge, uint16 chainId) {
        bridgePool = bridge;
        dolaChainId = chainId;
    }

    function getNonce() internal returns (uint64) {
        uint64 nonce = dolaNonce;
        dolaNonce++;
        return nonce;
    }

    function tokenDecimals(address token) internal view returns (uint8) {
        uint8 decimal = 18;
        if (token != address(0)) {
            decimal = IERC20(token).decimals();
        }
        return decimal;
    }

    function as_collateral(uint16[] memory dolaPoolIds) external payable {
        IWormholeBridge(bridgePool).sendLendingHelperPayload(
            dolaPoolIds,
            AS_COLLATERAL
        );
    }

    function cancel_as_collateral(uint16[] memory dolaPoolIds)
        external
        payable
    {
        IWormholeBridge(bridgePool).sendLendingHelperPayload(
            dolaPoolIds,
            CANCEL_AS_COLLATERAL
        );
    }

    function binding(uint16 bindDolaChainId, bytes memory bindAddress)
        external
        payable
    {
        uint64 nonce = getNonce();
        IWormholeBridge(bridgePool).sendProtocolPayload(
            nonce,
            BINDING,
            bindDolaChainId,
            bindAddress
        );
        emit ProtocolPortalEvent(
            nonce,
            msg.sender,
            dolaChainId,
            bindDolaChainId,
            bindAddress,
            BINDING
        );
    }

    function unbinding(uint16 unbindDolaChainId, bytes memory unbindAddress)
        external
        payable
    {
        uint64 nonce = getNonce();
        IWormholeBridge(bridgePool).sendProtocolPayload(
            nonce,
            UNBINDING,
            unbindDolaChainId,
            unbindAddress
        );
        emit ProtocolPortalEvent(
            nonce,
            msg.sender,
            dolaChainId,
            unbindDolaChainId,
            unbindAddress,
            UNBINDING
        );
    }

    function supply(address token, uint256 amount) external payable {
        uint64 nonce = getNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            tokenDecimals(token)
        );
        bytes memory appPayload = LibLending.encodeLendingAppPayload(
            dolaChainId,
            nonce,
            SUPPLY,
            fixAmount,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value: msg.value}(
            token,
            amount,
            LENDING_APP_ID,
            appPayload
        );
        emit LendingPortalEvent(
            nonce,
            msg.sender,
            abi.encodePacked(token),
            dolaChainId,
            0,
            abi.encodePacked(msg.sender),
            fixAmount,
            SUPPLY
        );
    }

    // withdraw use 8 decimal
    function withdraw(
        bytes memory token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    ) external payable {
        uint64 nonce = getNonce();
        bytes memory appPayload = LibLending.encodeLendingAppPayload(
            dolaChainId,
            nonce,
            WITHDRAW,
            amount,
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value: msg.value}(
            token,
            LENDING_APP_ID,
            appPayload
        );
        emit LendingPortalEvent(
            nonce,
            msg.sender,
            abi.encodePacked(token),
            dolaChainId,
            dstChainId,
            receiver,
            amount,
            WITHDRAW
        );
    }

    function borrow(
        bytes memory token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    ) external payable {
        uint64 nonce = getNonce();
        bytes memory appPayload = LibLending.encodeLendingAppPayload(
            dolaChainId,
            nonce,
            BORROW,
            amount,
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value: msg.value}(
            token,
            LENDING_APP_ID,
            appPayload
        );
        emit LendingPortalEvent(
            nonce,
            msg.sender,
            abi.encodePacked(token),
            dolaChainId,
            dstChainId,
            receiver,
            amount,
            BORROW
        );
    }

    function repay(address token, uint256 amount) external payable {
        uint64 nonce = getNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            tokenDecimals(token)
        );
        bytes memory appPayload = LibLending.encodeLendingAppPayload(
            dolaChainId,
            nonce,
            REPAY,
            fixAmount,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value: msg.value}(
            token,
            amount,
            LENDING_APP_ID,
            appPayload
        );
        emit LendingPortalEvent(
            nonce,
            msg.sender,
            abi.encodePacked(token),
            dolaChainId,
            0,
            abi.encodePacked(msg.sender),
            fixAmount,
            REPAY
        );
    }

    function liquidate(
        address debtToken,
        uint256 amount,
        uint16 liquidateChainId,
        bytes memory liquidateTokenAddress,
        uint64 liquidateUserId
    ) external {
        uint64 nonce = getNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            tokenDecimals(debtToken)
        );
        bytes memory appPayload = LibLending.encodeLendingAppPayload(
            dolaChainId,
            nonce,
            LIQUIDATE,
            fixAmount,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            liquidateUserId
        );
        IWormholeBridge(bridgePool).sendDepositAndWithdraw(
            debtToken,
            amount,
            liquidateChainId,
            liquidateTokenAddress,
            LENDING_APP_ID,
            appPayload
        );

        emit LendingPortalEvent(
            nonce,
            msg.sender,
            abi.encodePacked(debtToken),
            dolaChainId,
            0,
            abi.encodePacked(msg.sender),
            fixAmount,
            LIQUIDATE
        );
    }

    function generateNonce() internal returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}
