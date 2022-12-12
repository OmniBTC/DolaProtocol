// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";

library LibLending {
    using LibBytes for bytes;

    struct LendingAppPayload {
        uint16 dstChainId;
        uint64 amount;
        bytes user;
        uint8 callType;
    }

    function encodeAppPayload(
        uint8 callType,
        uint64 amount,
        bytes memory user,
        uint16 dstChainId
    ) internal pure returns (bytes memory) {
        bytes memory encodeData = abi.encodePacked(
            dstChainId,
            amount,
            uint16(user.length),
            user,
            callType
        );
        return encodeData;
    }

    function decodeAppPayload(bytes memory _payload)
        internal
        pure
        returns (LendingAppPayload memory)
    {
        uint256 length = _payload.length;
        uint256 index;
        uint256 dataLen;
        LendingAppPayload memory decodeData;

        dataLen = 2;
        decodeData.dstChainId = _payload.toUint16(index);
        index += dataLen;

        dataLen = 8;
        decodeData.amount = _payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 userLength = _payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = _payload.slice(index, index + dataLen);
        index += dataLen;

        dataLen = 1;
        decodeData.callType = _payload.toUint8(index);
        index += dataLen;
        require(index == length, "decode app payload error");
        return decodeData;
    }
}
