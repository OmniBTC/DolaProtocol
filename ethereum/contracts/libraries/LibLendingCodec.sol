// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibLendingCodec {
    using LibBytes for bytes;

    uint8 internal constant SUPPLY = 0;
    uint8 internal constant WITHDRAW = 1;
    uint8 internal constant BORROW = 2;
    uint8 internal constant REPAY = 3;
    uint8 internal constant LIQUIDATE = 4;
    uint8 internal constant AS_COLLATERAL = 5;
    uint8 internal constant CANCEL_AS_COLLATERAL = 6;

    struct DepositPayload {
        uint16 sourceChainId;
        uint64 nonce;
        LibDolaTypes.DolaAddress receiver;
        uint8 callType;
    }

    struct WithdrawPayload {
        uint16 sourceChainId;
        uint64 nonce;
        uint64 amount;
        LibDolaTypes.DolaAddress poolAddress;
        LibDolaTypes.DolaAddress receiver;
        uint8 callType;
    }

    struct LiquidatePayload {
        uint16 sourceChainId;
        uint64 nonce;
        LibDolaTypes.DolaAddress withdrawPool;
        uint64 liquidateUserId;
        uint8 callType;
    }

    struct ManageCollateralPayload {
        uint16[] dolaPoolIds;
        uint8 callType;
    }

    function encodeDepositPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory receiver,
        uint8 callType
    ) internal pure returns (bytes memory) {
        bytes memory dolaAddress = LibDolaTypes.encodeDolaAddress(
            receiver.dolaChainId,
            receiver.externalAddress
        );
        bytes memory encodeData = abi.encodePacked(
            sourceChainId,
            nonce,
            uint16(dolaAddress.length),
            dolaAddress,
            callType
        );
        return encodeData;
    }

    function decodeDepositPayload(bytes memory payload)
        internal
        pure
        returns (DepositPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        DepositPayload memory decodeData;

        dataLen = 2;
        decodeData.sourceChainId = payload.toUint16(index);
        index += dataLen;

        dataLen = 8;
        decodeData.nonce = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 receiveLength = payload.toUint16(index);
        index += dataLen;

        dataLen = receiveLength;
        decodeData.receiver = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "INVALID LENGTH");

        return decodeData;
    }

    function encodeWithdrawPayload(
        uint16 sourceChainId,
        uint64 nonce,
        uint64 amount,
        LibDolaTypes.DolaAddress memory poolAddress,
        LibDolaTypes.DolaAddress memory receiver,
        uint8 callType
    ) internal pure returns (bytes memory) {
        bytes memory poolDolaAddress = LibDolaTypes.encodeDolaAddress(
            poolAddress.dolaChainId,
            poolAddress.externalAddress
        );
        bytes memory receiverDolaAddress = LibDolaTypes.encodeDolaAddress(
            receiver.dolaChainId,
            receiver.externalAddress
        );
        bytes memory encodeData = abi.encodePacked(
            sourceChainId,
            nonce,
            amount,
            uint16(poolDolaAddress.length),
            poolDolaAddress,
            uint16(receiverDolaAddress.length),
            receiverDolaAddress,
            callType
        );
        return encodeData;
    }

    function decodeWithdrawPayload(bytes memory payload)
        internal
        pure
        returns (WithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        WithdrawPayload memory decodeData;

        dataLen = 2;
        decodeData.sourceChainId = payload.toUint16(index);
        index += dataLen;

        dataLen = 8;
        decodeData.nonce = payload.toUint64(index);
        index += dataLen;

        dataLen = 8;
        decodeData.amount = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 poolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = poolLength;
        decodeData.poolAddress = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 receiveLength = payload.toUint16(index);
        index += dataLen;

        dataLen = receiveLength;
        decodeData.receiver = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "INVALID LENGTH");

        return decodeData;
    }

    function encodeLiquidatePayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory withdrawPool,
        uint64 liquidateUserId
    ) internal pure returns (bytes memory) {
        bytes memory dolaAddress = LibDolaTypes.encodeDolaAddress(
            withdrawPool.dolaChainId,
            withdrawPool.externalAddress
        );
        bytes memory encodeData = abi.encodePacked(
            sourceChainId,
            nonce,
            uint16(dolaAddress.length),
            dolaAddress,
            liquidateUserId,
            LIQUIDATE
        );
        return encodeData;
    }

    function decodeLiquidatePayload(bytes memory payload)
        internal
        pure
        returns (LiquidatePayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        LiquidatePayload memory decodeData;

        dataLen = 2;
        decodeData.sourceChainId = payload.toUint16(index);
        index += dataLen;

        dataLen = 8;
        decodeData.nonce = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 poolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = poolLength;
        decodeData.withdrawPool = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 8;
        decodeData.liquidateUserId = payload.toUint64(index);
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(decodeData.callType == LIQUIDATE, "INVALID CALL TYPE");
        require(index == length, "INVALID LENGTH");

        return decodeData;
    }

    function encodeManageCollateralPayload(
        uint16[] memory dolaPoolIds,
        uint8 callType
    ) internal pure returns (bytes memory) {
        bytes memory encodeData = abi.encodePacked(uint16(dolaPoolIds.length));

        for (uint256 i = 0; i < dolaPoolIds.length; i++) {
            encodeData = encodeData.concat(abi.encodePacked(dolaPoolIds[i]));
        }

        encodeData = encodeData.concat(abi.encodePacked(callType));
        return encodeData;
    }

    function decodeManageCollateralPayload(bytes memory payload)
        internal
        pure
        returns (ManageCollateralPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        ManageCollateralPayload memory decodeData;

        dataLen = 2;
        uint16 poolIdsLength = payload.toUint16(index);
        index += dataLen;

        uint16[] memory dolaPoolIds = new uint16[](poolIdsLength);
        for (uint256 i = 0; i < poolIdsLength; i++) {
            dataLen = 2;
            uint16 dolaPoolId = payload.toUint16(index);
            index += dataLen;
            dolaPoolIds[i] = dolaPoolId;
        }
        decodeData.dolaPoolIds = dolaPoolIds;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "INVALID LENGTH");

        return decodeData;
    }
}
