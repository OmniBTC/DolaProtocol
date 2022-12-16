// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";

library LibDolaTypes {
    using LibBytes for bytes;

    struct DolaAddress {
        uint16 dolaChainId;
        bytes externalAddress;
    }

    function addressToDolaAddress(uint16 chainId, address evmAddress)
        internal
        pure
        returns (DolaAddress memory)
    {
        return DolaAddress(chainId, abi.encodePacked(evmAddress));
    }

    function dolaAddressToAddress(DolaAddress memory dolaAddress)
        internal
        pure
        returns (address)
    {
        require(
            dolaAddress.externalAddress.length == 20,
            "Not normal evm address"
        );
        return dolaAddress.externalAddress.toAddress(0);
    }

    function encodeDolaAddress(uint16 dolaChainId, bytes memory externalAddress)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory payload = abi.encodePacked(dolaChainId, externalAddress);
        return payload;
    }

    function decodeDolaAddress(bytes memory payload)
        internal
        pure
        returns (DolaAddress memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        DolaAddress memory dolaAddress;

        dataLen = 2;
        dolaAddress.dolaChainId = payload.toUint16(index);
        index = index + dataLen;

        dolaAddress.externalAddress = payload.slice(index, length);
        return dolaAddress;
    }
}
