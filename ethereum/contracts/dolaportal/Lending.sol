// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IWormholeAdapterPool.sol";
import "../../interfaces/IOmniPool.sol";
import "../libraries/LibLendingCodec.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";
import "../libraries/LibAsset.sol";

contract DolaPortal {
    uint8 public constant LENDING_APP_ID = 1;
    IWormholeAdapterPool immutable wormholeAdapterPool;
    uint64 public dolaNonce;

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

    constructor(IWormholeAdapterPool _wormholeAdapterPool) {
        wormholeAdapterPool = _wormholeAdapterPool;
    }

    function getNonce() internal returns (uint64) {
        uint64 nonce = dolaNonce;
        dolaNonce++;
        return nonce;
    }

    function supply(address token, uint256 amount) external payable {
        uint64 nonce = getNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            LibAsset.queryDecimals(token)
        );
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();
        bytes memory appPayload = LibLendingCodec.encodeDepositPayload(
            dolaChainId,
            nonce,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            LibLendingCodec.SUPPLY
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendDeposit{value: msg.value}(
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
            LibLendingCodec.SUPPLY
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
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibLendingCodec.encodeWithdrawPayload(
            dolaChainId,
            nonce,
            amount,
            LibDolaTypes.DolaAddress(dolaChainId, token),
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            LibLendingCodec.WITHDRAW
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
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
            LibLendingCodec.WITHDRAW
        );
    }

    function borrow(
        bytes memory token,
        bytes memory receiver,
        uint16 dstChainId,
        uint64 amount
    ) external payable {
        uint64 nonce = getNonce();
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibLendingCodec.encodeWithdrawPayload(
            dolaChainId,
            nonce,
            amount,
            LibDolaTypes.DolaAddress(dolaChainId, token),
            LibDolaTypes.DolaAddress(dstChainId, receiver),
            LibLendingCodec.BORROW
        );

        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
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
            LibLendingCodec.BORROW
        );
    }

    function repay(address token, uint256 amount) external payable {
        uint64 nonce = getNonce();
        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            LibAsset.queryDecimals(token)
        );
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibLendingCodec.encodeDepositPayload(
            dolaChainId,
            nonce,
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            LibLendingCodec.REPAY
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendDeposit{value: msg.value}(
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
            LibLendingCodec.REPAY
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
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        uint64 fixAmount = LibDecimals.fixAmountDecimals(
            amount,
            LibAsset.queryDecimals(debtToken)
        );
        bytes memory appPayload = LibLendingCodec.encodeLiquidatePayload(
            dolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(dolaChainId, liquidateTokenAddress),
            liquidateUserId
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendDeposit(
            debtToken,
            amount,
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
            LibLendingCodec.LIQUIDATE
        );
    }

    function as_collateral(uint16[] memory dolaPoolIds) external payable {
        uint64 nonce = getNonce();

        bytes memory appPayload = LibLendingCodec.encodeManageCollateralPayload(
            dolaPoolIds,
            LibLendingCodec.AS_COLLATERAL
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            LENDING_APP_ID,
            appPayload
        );
    }

    function cancel_as_collateral(uint16[] memory dolaPoolIds)
        external
        payable
    {
        uint64 nonce = getNonce();

        bytes memory appPayload = LibLendingCodec.encodeManageCollateralPayload(
            dolaPoolIds,
            LibLendingCodec.CANCEL_AS_COLLATERAL
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            LENDING_APP_ID,
            appPayload
        );
    }

    function generateNonce() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}
