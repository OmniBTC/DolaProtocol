// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibPoolCodec {
    using LibBytes for bytes;

    uint8 internal constant POOL_DEPOSIT = 0;
    uint8 internal constant POOL_WITHDRAW = 1;
    uint8 internal constant POOL_SEND_MESSAGE = 2;
    uint8 internal constant POOL_REGISTER_OWNER = 3;
    uint8 internal constant POOL_REGISTER_SPENDER = 4;
    uint8 internal constant POOL_DELETE_OWNER = 5;
    uint8 internal constant POOL_DELETE_SPENDER = 6;

    struct DepositPayload {
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint64 amount;
        uint16 appId;
        uint8 poolCallType;
        bytes appPayload;
    }

    struct SendMessagePayload {
        LibDolaTypes.DolaAddress user;
        uint16 appId;
        uint8 poolCallType;
        bytes appPayload;
    }

    struct WithdrawPayload {
        uint16 sourceChainId;
        uint64 nonce;
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint64 amount;
        uint8 poolCallType;
    }

    struct ManagePoolPayload {
        uint16 dolaChainId;
        uint256 dolaContract;
        uint8 poolCallType;
    }

    /// Encode and decode

    /// Encoding of Pool Messages with Funding
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
            appId,
            uint16(poolAddress.length),
            poolAddress,
            uint16(userAddress.length),
            userAddress,
            amount,
            POOL_DEPOSIT
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
        decodeData.appId = payload.toUint16(index);
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

        dataLen = 1;
        decodeData.poolCallType = payload.toUint8(index);
        index += dataLen;

        if (index < length) {
            dataLen = 2;
            uint16 appPayloadLength = payload.toUint16(index);
            index += dataLen;

            dataLen = appPayloadLength;
            decodeData.appPayload = payload.slice(index, dataLen);
            index += dataLen;
        }
        require(decodeData.poolCallType == POOL_DEPOSIT, "INVALID CALL TYPE");
        require(index == length, "INVALID LENGTH");

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
            amount,
            POOL_WITHDRAW
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

        dataLen = 1;
        decodeData.poolCallType = payload.toUint8(index);
        index += dataLen;

        require(decodeData.poolCallType == POOL_WITHDRAW, "INVALID CALL TYPE");
        require(index == length, "INVALID LENGTH");

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
            appId,
            uint16(userAddress.length),
            userAddress,
            POOL_SEND_MESSAGE
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
        decodeData.appId = payload.toUint16(index);
        index += dataLen;

        dataLen = 2;
        uint16 userLength = payload.toUint16(index);
        index += dataLen;

        dataLen = userLength;
        decodeData.user = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 1;
        decodeData.poolCallType = payload.toUint8(index);
        index += dataLen;

        if (index < length) {
            dataLen = 2;
            uint16 appPayloadLength = payload.toUint16(index);
            index += dataLen;

            dataLen = appPayloadLength;
            decodeData.appPayload = payload.slice(index, dataLen);
            index += dataLen;
        }
        require(
            decodeData.poolCallType == POOL_SEND_MESSAGE,
            "INVALID CALL TYPE"
        );
        require(index == length, "INVALID LENGTH");

        return decodeData;
    }

    function encodeManagePoolPayload(
        uint16 dolaChainId,
        uint256 dolaContract,
        uint8 poolCallType
    ) internal pure returns (bytes memory) {
        bytes memory payload = abi.encodePacked(
            dolaChainId,
            dolaContract,
            poolCallType
        );
        return payload;
    }

    function decodeManagePoolPayload(bytes memory payload)
        internal
        pure
        returns (ManagePoolPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        ManagePoolPayload memory decodeData;

        dataLen = 2;
        decodeData.dolaChainId = payload.toUint16(index);
        index += dataLen;

        dataLen = 32;
        decodeData.dolaContract = payload.toUint256(index);
        index += dataLen;

        dataLen = 1;
        decodeData.poolCallType = payload.toUint8(index);
        index += dataLen;

        require(index == length, "INVALID LENGTH");

        return decodeData;
    }
}
