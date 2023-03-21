// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IWormholeAdapterPool.sol";
import "../libraries/LibLendingCodec.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";
import "../libraries/LibAsset.sol";

contract LendingPortal {
    uint8 public constant LENDING_APP_ID = 1;
    IWormholeAdapterPool immutable wormholeAdapterPool;
    address payable public relayer;

    event RelayEvent(uint32 nonce, uint256 amount);

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
        relayer = payable(msg.sender);
    }

    function supply(
        address token,
        uint256 amount,
        uint256 fee
    ) external payable {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
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
        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.maxApproveERC20(
                IERC20(token),
                address(wormholeAdapterPool),
                amount
            );
        }

        IWormholeAdapterPool(wormholeAdapterPool).sendDeposit{
        value : msg.value - fee
        }(token, amount, LENDING_APP_ID, appPayload);

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
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
        uint64 amount,
        uint256 fee
    ) external payable {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
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

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
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
        uint64 amount,
        uint256 fee
    ) external payable {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
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

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
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

    function repay(
        address token,
        uint256 amount,
        uint256 fee
    ) external payable {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
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

        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.maxApproveERC20(
                IERC20(token),
                address(wormholeAdapterPool),
                amount
            );
        }

        IWormholeAdapterPool(wormholeAdapterPool).sendDeposit{value : msg.value}(
            token,
            amount,
            LENDING_APP_ID,
            appPayload
        );

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
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
        uint64 liquidateUserId,
        uint256 fee
    ) external {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
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

        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(debtToken, amount);

        IWormholeAdapterPool(wormholeAdapterPool).sendDeposit(
            debtToken,
            amount,
            LENDING_APP_ID,
            appPayload
        );

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
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

    function as_collateral(uint16[] memory dolaPoolIds, uint256 fee)
    external
    payable
    {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();

        bytes memory appPayload = LibLendingCodec.encodeManageCollateralPayload(
            dolaPoolIds,
            LibLendingCodec.AS_COLLATERAL
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            LENDING_APP_ID,
            appPayload
        );

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
        );
    }

    function cancel_as_collateral(uint16[] memory dolaPoolIds, uint256 fee)
    external
    payable
    {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();

        bytes memory appPayload = LibLendingCodec.encodeManageCollateralPayload(
            dolaPoolIds,
            LibLendingCodec.CANCEL_AS_COLLATERAL
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            LENDING_APP_ID,
            appPayload
        );

        relayer.transfer(fee);

        emit RelayEvent(
            nonce,
            fee
        );
    }
}
