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
    address public bridgePool;
    uint16 public dolaChainId;

    event ProtocolPortalEvent(
        bytes32 nonce,
        address sender,
        uint16 sendChainId,
        uint16 userChainId,
        bytes userAddress,
        uint8 callType
    );
    event LendingPortalEvent(
        bytes32 nonce,
        address sender,
        bytes dolaPoolAddress,
        uint16 sendChainId,
        uint16 receiveChianId,
        bytes receiver,
        uint64 amount,
        uint8 callType
    );

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

    function binding(uint16 bindDolaChainId, bytes memory bindAddress)
    external
    payable
    {
        IWormholeBridge(bridgePool).sendBinding(bindDolaChainId, bindAddress);
        emit ProtocolPortalEvent(
            generateNonce(),
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
        IWormholeBridge(bridgePool).sendBinding(
            unbindDolaChainId,
            unbindAddress
        );
        emit ProtocolPortalEvent(
            generateNonce(),
            msg.sender,
            dolaChainId,
            unbindDolaChainId,
            unbindAddress,
            UNBINDING
        );
    }

    function supply(address token, uint256 amount) external payable {
        bytes32 nonce = generateNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            tokenDecimals(token)
        );
        bytes memory appPayload = LibLending.encodeAppPayload(
            nonce,
            SUPPLY,
            fixAmount,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value : msg.value}(
            token,
            fixAmount,
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
        bytes32 nonce = generateNonce();
        bytes memory appPayload = LibLending.encodeAppPayload(
            nonce,
            WITHDRAW,
            amount,
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value : msg.value}(
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
        bytes32 nonce = generateNonce();
        bytes memory appPayload = LibLending.encodeAppPayload(
            nonce,
            BORROW,
            amount,
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            0
        );
        IWormholeBridge(bridgePool).sendWithdraw{value : msg.value}(
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
        bytes32 nonce = generateNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            tokenDecimals(token)
        );
        bytes memory appPayload = LibLending.encodeAppPayload(
            nonce,
            REPAY,
            fixAmount,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            0
        );
        IWormholeBridge(bridgePool).sendDeposit{value : msg.value}(
            token,
            fixAmount,
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
        bytes memory receiver,
        uint16 dstChainId,
        address debtToken,
        uint256 amount,
        address collateralToken,
        uint64 liquidateUserId
    ) external {
        bytes32 nonce = generateNonce();
        bytes memory appPayload = LibLending.encodeAppPayload(
            nonce,
            LIQUIDATE,
            LibDecimals.fixAmountDecimals(amount, tokenDecimals(debtToken)),
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            liquidateUserId
        );
        IWormholeBridge(bridgePool).sendDepositAndWithdraw(
            debtToken,
            amount,
            collateralToken,
            LENDING_APP_ID,
            appPayload
        );
    }

    function generateNonce() internal returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}
