// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibDolaTypes.sol";

library LibPool {
    using LibBytes for bytes;

    struct SendDepositPayload {
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint64 amount;
        uint16 appId;
        bytes appPayload;
    }

    struct SendWithdrawPayload {
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint16 appId;
        bytes appPayload;
    }

    struct SendDepositAndWithdrawPayload {
        LibDolaTypes.DolaAddress depositPool;
        LibDolaTypes.DolaAddress depositUser;
        uint64 depositAmount;
        LibDolaTypes.DolaAddress withdrawPool;
        uint16 appId;
        bytes appPayload;
    }

    struct ReceiveWithdrawPayload {
        LibDolaTypes.DolaAddress pool;
        LibDolaTypes.DolaAddress user;
        uint64 amount;
    }

    function encodeSendDepositPayload(
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

    function decodeSendDepositPayload(bytes memory payload)
        internal
        pure
        returns (SendDepositPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendDepositPayload memory decodeData;

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

    function encodeSendWithdrawPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
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
            appId
        );

        if (appPayload.length > 0) {
            payload = payload.concat(
                abi.encodePacked(uint16(appPayload.length), appPayload)
            );
        }
        return payload;
    }

    function decodeSendWithdrawPayload(bytes memory payload)
        internal
        pure
        returns (SendWithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendWithdrawPayload memory decodeData;

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

    function encodeSendDepositAndWithdrawPayload(
        LibDolaTypes.DolaAddress memory depositPool,
        LibDolaTypes.DolaAddress memory depositUser,
        uint64 depositAmount,
        LibDolaTypes.DolaAddress memory withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) internal pure returns (bytes memory) {
        bytes memory depositPoolAddress = LibDolaTypes.encodeDolaAddress(
            depositPool.dolaChainId,
            depositPool.externalAddress
        );
        bytes memory depositUserAddress = LibDolaTypes.encodeDolaAddress(
            depositUser.dolaChainId,
            depositUser.externalAddress
        );
        bytes memory withdrawPoolAddress = LibDolaTypes.encodeDolaAddress(
            withdrawPool.dolaChainId,
            withdrawPool.externalAddress
        );
        bytes memory payload = abi.encodePacked(
            uint16(depositPoolAddress.length),
            depositPoolAddress,
            uint16(depositUserAddress.length),
            depositUserAddress,
            depositAmount,
            uint16(withdrawPoolAddress.length),
            withdrawPoolAddress,
            appId
        );

        if (appPayload.length > 0) {
            payload = payload.concat(
                abi.encodePacked(uint16(appPayload.length), appPayload)
            );
        }
        return payload;
    }

    function decodeSendDepositAndWithdrawPayload(bytes memory payload)
        internal
        pure
        returns (SendDepositAndWithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendDepositAndWithdrawPayload memory decodeData;

        dataLen = 2;
        uint16 depositPoolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = depositPoolLength;
        decodeData.depositPool = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 2;
        uint16 depositUserLength = payload.toUint16(index);
        index += dataLen;

        dataLen = depositUserLength;
        decodeData.depositUser = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );
        index += dataLen;

        dataLen = 8;
        decodeData.depositAmount = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 withdrawPoolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = withdrawPoolLength;
        decodeData.withdrawPool = LibDolaTypes.decodeDolaAddress(
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
        require(
            index == length,
            "Decode send deposit and withdraw payload error"
        );

        return decodeData;
    }

    function encodeReceiveWithdrawPayload(
        address pool,
        address user,
        uint64 amount,
        bytes memory tokenName
    ) internal pure returns (bytes memory) {
        bytes memory payload = abi.encodePacked(
            pool,
            user,
            amount,
            uint16(tokenName.length),
            tokenName
        );

        return payload;
    }

    function decodeReceiveWithdrawPayload(bytes memory payload)
        internal
        pure
        returns (ReceiveWithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        ReceiveWithdrawPayload memory decodeData;

        dataLen = 2;
        uint16 poolLength = payload.toUint16(index);
        index += dataLen;

        dataLen = poolLength;
        decodeData.pool = LibDolaTypes.decodeDolaAddress(
            payload.slice(index, dataLen)
        );

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
