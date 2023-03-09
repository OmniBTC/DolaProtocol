// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibPool {
    using LibBytes for bytes;

    struct DepositPayload {
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint64 amount;
        uint16 appId;
        bytes appPayload;
    }

    struct SendMessagePayload {
        LibDolaTypes.DolaAddress user;
        uint16 appId;
        bytes appPayload;
    }

    struct WithdrawPayload {
        uint16 sourceChainId;
        uint64 nonce;
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint64 amount;
    }

    function encodeDepositPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount,
        uint16 appId,
        bytes memory appPayload
    ) internal pure returns (bytes memory) {
        bytes memory poolAddress = LibDolaTypes.encodeDolaAddress(
            pool.dolaChainId,
            pool.externalAddress
        );
        bytes memory userAddress = LibDolaTypes.encodeDolaAddress(
            user.dolaChainId,
            user.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            uint16(poolAddress.length),
            poolAddress,
            uint16(userAddress.length),
            userAddress,
            amount,
            appId
        );

        if (appPayload.length > 0) {
            payload = payload.concat(
                abi.encodePacked(uint16(appPayload.length), appPayload)
            );
        }
        return payload;
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
        uint16 poolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = poolLength;
        decodeData.pool = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 8;
        decodeData.amount = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        decodeData.appId = payload.toUint16(index);
        index += dataLen;

        if (index < length) {
            dataLen = 2;
            uint16 appPayloadLength = payload.toUint16(index);
            index += dataLen;

            dataLen = appPayloadLength;
            decodeData.appPayload = payload.slice(index, dataLen);
            index += dataLen;
        }
        require(index == length, "Decode send deposit payload error");

        return decodeData;
    }

    function encodeSendMessagePayload(
        LibDolaTypes.DolaAddress memory user,
        uint16 appId,
        bytes memory appPayload
    ) internal pure returns (bytes memory) {
        bytes memory userAddress = LibDolaTypes.encodeDolaAddress(
            user.dolaChainId,
            user.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            uint16(userAddress.length),
            userAddress,
            appId
        );

        if (appPayload.length > 0) {
            payload = payload.concat(
                abi.encodePacked(uint16(appPayload.length), appPayload)
            );
        }
        return payload;
    }

    function decodeSendMessagePayload(bytes memory payload)
    internal
    pure
    returns (SendMessagePayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendMessagePayload memory decodeData;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        decodeData.appId = payload.toUint16(index);
        index += dataLen;

        if (index < length) {
            dataLen = 2;
            uint16 appPayloadLength = payload.toUint16(index);
            index += dataLen;

            dataLen = appPayloadLength;
            decodeData.appPayload = payload.slice(index, dataLen);
            index += dataLen;
        }
        require(index == length, "Decode send deposit payload error");

        return decodeData;
    }

    function encodeWithdrawPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount
    ) internal pure returns (bytes memory) {
        bytes memory poolAddress = LibDolaTypes.encodeDolaAddress(
            pool.dolaChainId,
            pool.externalAddress
        );
        bytes memory userAddress = LibDolaTypes.encodeDolaAddress(
            user.dolaChainId,
            user.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            sourceChainId,
            nonce,
            uint16(poolAddress.length),
            poolAddress,
            uint16(userAddress.length),
            userAddress,
            amount
        );
        return payload;
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

        dataLen = 2;
        uint16 poolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = poolLength;
        decodeData.pool = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 8;
        decodeData.amount = payload.toUint64(index);
        index += dataLen;

        require(index == length, "Decode receive withdraw payload error");

        return decodeData;
    }
}
