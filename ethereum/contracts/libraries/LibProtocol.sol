// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibProtocol {
    using LibBytes for bytes;
    uint16 internal constant APP_ID = 0;

    struct ProtocolAppPayload {
        uint16 appId;
        uint16 sourceChainId;
        uint64 nonce;
        LibDolaTypes.DolaAddress sender;
        LibDolaTypes.DolaAddress userAddress;
        uint8 callType;
    }

    function encodeProtocolAppPayload(
        uint16 sourceChainId,
        uint64 nonce,
        uint8 callType,
        LibDolaTypes.DolaAddress memory user,
        LibDolaTypes.DolaAddress memory binding
    ) internal pure returns (bytes memory) {
        bytes memory userAddress = LibDolaTypes.encodeDolaAddress(
            user.dolaChainId,
            user.externalAddress
        );
        bytes memory bindingAddress = LibDolaTypes.encodeDolaAddress(
            binding.dolaChainId,
            binding.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            APP_ID,
            sourceChainId,
            nonce,
            uint16(userAddress.length),
            userAddress,
            uint16(bindingAddress.length),
            bindingAddress,
            callType
        );
        return payload;
    }

    function decodeProtocolAppPayload(bytes memory payload)
        internal
        pure
        returns (ProtocolAppPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        ProtocolAppPayload memory decodeData;

        dataLen = 2;
        decodeData.appId = payload.toUint16(index);
        index += dataLen;

        dataLen = 2;
        decodeData.sourceChainId = payload.toUint16(index);
        index += dataLen;

        dataLen = 8;
        decodeData.nonce = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 senderLength = payload.toUint16(index);
        index += dataLen;

        dataLen = senderLength;
        decodeData.sender = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
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

        require(index == length, "Decode unbinding payload error");

        return decodeData;
    }
}
