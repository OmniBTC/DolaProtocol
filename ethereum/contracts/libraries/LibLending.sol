// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibLending {
    using LibBytes for bytes;

    struct LendingAppPayload {
        bytes txid;
        uint8 callType;
        uint64 amount;
        LibDolaTypes.DolaAddress receiver;
        uint64 liquidateUserId;
    }

    function encodeAppPayload(
        bytes memory txid,
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
            uint16(txid.length),
            txid,
            amount,
            uint16(dolaAddress.length),
            dolaAddress,
            liquidateUserId,
            callType
        );
        return encodeData;
    }

    function decodeAppPayload(bytes memory payload)
    internal
    pure
    returns (LendingAppPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        LendingAppPayload memory decodeData;

        dataLen = 2;
        uint16 txidLength = payload.toUint16(index);
        index += dataLen;

        dataLen = txidLength;
        decodeData.txid = payload.slice(index, index + dataLen);
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
