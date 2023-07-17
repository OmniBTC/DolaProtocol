// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibGovCodec {
    using LibBytes for bytes;

    uint8 internal constant ADD_RELAYER_OPCODE = 0;
    uint8 internal constant REMOVE_RELAYER_OPCODE = 1;

    struct RelayerPayload {
        LibDolaTypes.DolaAddress relayer;
        uint8 opcode;
    }

    function encodeRelayerPayload(
        LibDolaTypes.DolaAddress memory relayer,
        uint8 opcode
    ) internal pure returns (bytes memory) {
        bytes memory relayerAddress = LibDolaTypes.encodeDolaAddress(
            relayer.dolaChainId,
            relayer.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            uint16(relayerAddress.length),
            relayerAddress,
            opcode
        );
        return payload;
    }

    function decodeRelayerPayload(bytes memory payload)
        internal
        pure
        returns (RelayerPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        RelayerPayload memory decodeData;

        dataLen = 2;
        uint16 relayerLength = payload.toUint16(index);
        index += dataLen;

        dataLen = relayerLength;
        decodeData.relayer = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.opcode = payload.toUint8(index);
        index += dataLen;

        require(index == length, "INVALID LENGTH");

        return decodeData;
    }
}
