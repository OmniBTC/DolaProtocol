// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibLending {
    using LibBytes for bytes;

    struct LendingAppPayload {
        uint16 sourceChainId;
        uint64 nonce;
        uint8 callType;
        uint64 amount;
        LibDolaTypes.DolaAddress receiver;
        uint64 liquidateUserId;
    }

    struct LendingAppHelperPayload {
        LibDolaTypes.DolaAddress sender;
        uint16[] dolaPoolIds;
        uint8 callType;
    }

    function encodeAppHelperPayload(
        LibDolaTypes.DolaAddress memory sender,
        uint16[] memory dolaPoolIds,
        uint8 callType
    ) internal pure returns (bytes memory) {
        bytes memory dolaAddress = LibDolaTypes.encodeDolaAddress(
            sender.dolaChainId,
            sender.externalAddress
        );
        bytes memory encodeData = abi.encodePacked(
            uint16(dolaAddress.length),
            dolaAddress
        );
        for (uint256 i = 0; i < dolaPoolIds.length; i++) {
            encodeData.concat(abi.encodePacked(dolaPoolIds[i]));
        }

        encodeData.concat(abi.encodePacked(callType));
        return encodeData;
    }

    function decodeAppHelperPayload(bytes memory payload)
        internal
        pure
        returns (LendingAppHelperPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        LendingAppHelperPayload memory decodeData;

        dataLen = 2;
        uint16 senderLength = payload.toUint16(index);
        index += dataLen;

        dataLen = senderLength;
        decodeData.sender = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, index + dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 poolIdsLength = payload.toUint16(index);
        index += dataLen;

        for (uint256 i = 0; i < poolIdsLength; i++) {
            dataLen = 2;
            uint16 dolaPoolId = payload.toUint16(index);
            index += dataLen;
            decodeData.dolaPoolIds[i] = dolaPoolId;
        }

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "decode app helper payload error");

        return decodeData;
    }

    function encodeLendingAppPayload(
        uint16 sourceChainId,
        uint64 nonce,
        uint8 callType,
        uint64 amount,
        LibDolaTypes.DolaAddress memory receiver,
        uint64 liquidateUserId
    ) internal pure returns (bytes memory) {
        bytes memory dolaAddress = LibDolaTypes.encodeDolaAddress(
            receiver.dolaChainId,
            receiver.externalAddress
        );
        bytes memory encodeData = abi.encodePacked(
            sourceChainId,
            nonce,
            amount,
            uint16(dolaAddress.length),
            dolaAddress,
            liquidateUserId,
            callType
        );
        return encodeData;
    }

    function decodeLendingAppPayload(bytes memory payload)
        internal
        pure
        returns (LendingAppPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        LendingAppPayload memory decodeData;

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
        uint16 receiveLength = payload.toUint16(index);
        index += dataLen;

        dataLen = receiveLength;
        decodeData.receiver = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, index + dataLen)
        );
        index += dataLen;

        dataLen = 8;
        decodeData.liquidateUserId = payload.toUint64(index);
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "decode app payload error");

        return decodeData;
    }
}
