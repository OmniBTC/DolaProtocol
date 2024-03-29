// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibSystemCodec {
    using LibBytes for bytes;

    uint8 internal constant BINDING = 0;
    uint8 internal constant UNBINDING = 1;

    struct SystemBindPayload {
        uint16 sourceChainId;
        uint64 nonce;
        LibDolaTypes.DolaAddress userAddress;
        uint8 callType;
    }

    /// Encode binding or unbinding
    function encodeBindPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory binding,
        uint8 systemCallType
    ) internal pure returns (bytes memory) {
        bytes memory bindingAddress = LibDolaTypes.encodeDolaAddress(
            binding.dolaChainId,
            binding.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            sourceChainId,
            nonce,
            uint16(bindingAddress.length),
            bindingAddress,
            systemCallType
        );
        return payload;
    }

    /// Decode binding or unbinding
    function decodeBindPayload(bytes memory payload)
        internal
        pure
        returns (SystemBindPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SystemBindPayload memory decodeData;

        dataLen = 2;
        decodeData.sourceChainId = payload.toUint16(index);
        index += dataLen;

        dataLen = 8;
        decodeData.nonce = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.userAddress = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "INVALID LENGTH");

        return decodeData;
    }
}
