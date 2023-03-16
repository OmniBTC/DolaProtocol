// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../libraries//LibDolaTypes.sol";
import "../libraries//LibLendingCodec.sol";
import "../libraries//LibPoolCodec.sol";
import "../libraries//LibSystemCodec.sol";

contract EncodeDecode {
    /// Pool codec
    function encodeDepositPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return
            LibPoolCodec.encodeDepositPayload(
                pool,
                user,
                amount,
                appId,
                appPayload
            );
    }

    function decodeDepositPayload(bytes memory payload)
        external
        pure
        returns (LibPoolCodec.DepositPayload memory)
    {
        return LibPoolCodec.decodeDepositPayload(payload);
    }

    function encodeSendMessagePayload(
        LibDolaTypes.DolaAddress memory user,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return LibPoolCodec.encodeSendMessagePayload(user, appId, appPayload);
    }

    function decodeSendMessagePayload(bytes memory payload)
        external
        pure
        returns (LibPoolCodec.SendMessagePayload memory)
    {
        return LibPoolCodec.decodeSendMessagePayload(payload);
    }

    function encodeWithdrawPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount
    ) external pure returns (bytes memory) {
        return
            LibPoolCodec.encodeWithdrawPayload(
                sourceChainId,
                nonce,
                pool,
                user,
                amount
            );
    }

    function decodeWithdrawPayload(bytes memory payload)
        external
        pure
        returns (LibPoolCodec.WithdrawPayload memory)
    {
        return LibPoolCodec.decodeWithdrawPayload(payload);
    }

    /// Lending codec

    function encodeLendingDepositPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory receiver,
        uint8 callType
    ) external pure returns (bytes memory) {
        return
            LibLendingCodec.encodeDepositPayload(
                sourceChainId,
                nonce,
                receiver,
                callType
            );
    }

    function decodeLendingDepositPayload(bytes memory payload)
        external
        pure
        returns (LibLendingCodec.DepositPayload memory)
    {
        return LibLendingCodec.decodeDepositPayload(payload);
    }

    function encodeLendingWithdrawPayload(
        uint16 sourceChainId,
        uint64 nonce,
        uint64 amount,
        LibDolaTypes.DolaAddress memory poolAddress,
        LibDolaTypes.DolaAddress memory receiver,
        uint8 callType
    ) external pure returns (bytes memory) {
        return
            LibLendingCodec.encodeWithdrawPayload(
                sourceChainId,
                nonce,
                amount,
                poolAddress,
                receiver,
                callType
            );
    }

    function decodeLendingWithdrawPayload(bytes memory payload)
        external
        pure
        returns (LibLendingCodec.WithdrawPayload memory)
    {
        return LibLendingCodec.decodeWithdrawPayload(payload);
    }

    function encodeLendingLiquidatePayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory withdrawPool,
        uint64 liquidateUserId
    ) external pure returns (bytes memory) {
        return
            LibLendingCodec.encodeLiquidatePayload(
                sourceChainId,
                nonce,
                withdrawPool,
                liquidateUserId
            );
    }

    function decodeLendingLiquidatePayload(bytes memory payload)
        external
        pure
        returns (LibLendingCodec.LiquidatePayload memory)
    {
        return LibLendingCodec.decodeLiquidatePayload(payload);
    }

    function encodeManageCollateralPayload(
        uint16[] memory dolaPoolIds,
        uint8 callType
    ) external pure returns (bytes memory) {
        return
            LibLendingCodec.encodeManageCollateralPayload(
                dolaPoolIds,
                callType
            );
    }

    function decodeManageCollateralPayload(bytes memory payload)
        external
        pure
        returns (LibLendingCodec.ManageCollateralPayload memory)
    {
        return LibLendingCodec.decodeManageCollateralPayload(payload);
    }

    /// System codec

    function encodeBindPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory binding,
        uint8 systemCallType
    ) external pure returns (bytes memory) {
        return
            LibSystemCodec.encodeBindPayload(
                sourceChainId,
                nonce,
                binding,
                systemCallType
            );
    }

    function decodeBindPayload(bytes memory payload)
        external
        pure
        returns (LibSystemCodec.SystemBindPayload memory)
    {
        return LibSystemCodec.decodeBindPayload(payload);
    }
}
