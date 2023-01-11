// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibBinding {
    using LibBytes for bytes;
    uint8 internal constant BINDING = 5;
    uint8 internal constant UNBINDING = 6;

    struct BindingPayload {
        LibDolaTypes.DolaAddress user;
        LibDolaTypes.DolaAddress binding;
        uint8 callType;
    }

    struct UnbindingPayload {
        LibDolaTypes.DolaAddress user;
        LibDolaTypes.DolaAddress unbinding;
        uint8 callType;
    }

    function encodeBindingPayload(
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
            uint16(userAddress.length),
            userAddress,
            uint16(bindingAddress.length),
            bindingAddress,
            BINDING
        );
        return payload;
    }

    function encodeUnbindingPayload(
        LibDolaTypes.DolaAddress memory user,
        LibDolaTypes.DolaAddress memory unbinding
    ) internal pure returns (bytes memory) {
        bytes memory userAddress = LibDolaTypes.encodeDolaAddress(
            user.dolaChainId,
            user.externalAddress
        );
        bytes memory bindingAddress = LibDolaTypes.encodeDolaAddress(
            unbinding.dolaChainId,
            unbinding.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            uint16(userAddress.length),
            userAddress,
            uint16(bindingAddress.length),
            bindingAddress,
            UNBINDING
        );
        return payload;
    }

    function decodeUnbindingPayload(bytes memory payload)
        internal
        pure
        returns (UnbindingPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        UnbindingPayload memory decodeData;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 unbindingLength = payload.toUint16(index);
        index += dataLen;

        dataLen = unbindingLength;
        decodeData.unbinding = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "Decode unbinding payload error");

        return decodeData;
    }

    function decodeBindingPayload(bytes memory payload)
        internal
        pure
        returns (BindingPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        BindingPayload memory decodeData;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 bindingLength = payload.toUint16(index);
        index += dataLen;

        dataLen = bindingLength;
        decodeData.binding = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.callType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "Decode binding payload error");

        return decodeData;
    }
}
