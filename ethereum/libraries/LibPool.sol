// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";

library LibPool {
    using LibBytes for bytes;

    struct DepositPayload {
        address pool;
        address user;
        uint64 amount;
        bytes tokenName;
        uint16 appId;
        bytes appPayload;
    }

    struct WithdrawPayload {
        address pool;
        address user;
        bytes tokenName;
        uint16 appId;
        bytes appPayload;
    }

    struct DepositAndWithdrawPayload {
        address depositPool;
        address depositUser;
        uint64 depositAmount;
        bytes depositTokenName;
        address withdrawPool;
        address withdrawUser;
        bytes withdrawTokenName;
        uint16 appId;
        bytes appPayload;
    }

    function fixAmountDecimals(uint256 amount, uint8 decimals)
        public
        pure
        returns (uint64)
    {
        uint64 fixedAmount;
        if (decimals > 8) {
            fixedAmount = uint64(amount / (10**(decimals - 8)));
        } else if (decimals < 8) {
            fixedAmount = uint64(amount * (10**(8 - decimals)));
        } else {
            fixedAmount = uint64(amount);
        }
        require(fixedAmount > 0, "Fixed amount too low");
        return fixedAmount;
    }

    function restoreAmountDecimals(uint64 amount, uint8 decimals)
        public
        pure
        returns (uint256)
    {
        uint256 restoreAmount;
        if (decimals > 8) {
            restoreAmount = uint256(amount * (10**(decimals - 8)));
        } else if (decimals < 8) {
            restoreAmount = uint256(amount / (10**(8 - decimals)));
        } else {
            restoreAmount = uint256(amount);
        }
        return restoreAmount;
    }

    function encodeSendDepositPayload(
        address pool,
        address user,
        uint64 amount,
        bytes memory tokenName,
        uint16 appId,
        bytes memory appPayload
    ) public pure returns (bytes memory) {
        bytes memory payload = abi.encodePacked(
            pool,
            user,
            amount,
            uint16(tokenName.length),
            tokenName,
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
        public
        pure
        returns (DepositPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        DepositPayload memory decodeData;

        dataLen = 20;
        decodeData.pool = payload.toAddress(index);
        index += dataLen;

        dataLen = 20;
        decodeData.user = payload.toAddress(index);
        index += dataLen;

        dataLen = 8;
        decodeData.amount = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 tokenNameLength = payload.toUint16(index);
        index += dataLen;

        dataLen = tokenNameLength;
        decodeData.tokenName = payload.slice(index, dataLen);
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
        require(index == length, "Decode deposit payload error");

        return decodeData;
    }

    function encodeSendWithdrawPayload(
        address pool,
        address user,
        bytes memory tokenName,
        uint16 appId,
        bytes memory appPayload
    ) public pure returns (bytes memory) {
        bytes memory payload = abi.encodePacked(
            pool,
            user,
            uint16(tokenName.length),
            tokenName,
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
        public
        pure
        returns (WithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        WithdrawPayload memory decodeData;

        dataLen = 20;
        decodeData.pool = payload.toAddress(index);
        index += dataLen;

        dataLen = 20;
        decodeData.user = payload.toAddress(index);
        index += dataLen;

        dataLen = 2;
        uint16 tokenNameLength = payload.toUint16(index);
        index += dataLen;

        dataLen = tokenNameLength;
        decodeData.tokenName = payload.slice(index, dataLen);
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
        require(index == length, "Decode withdraw payload error");

        return decodeData;
    }

    function encodeSendDepositAndWithdrawPayload(
        address depositPool,
        address depositUser,
        uint64 depositAmount,
        bytes memory depositTokenName,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) public pure returns (bytes memory) {
        bytes memory payload = abi.encodePacked(
            depositPool,
            depositUser,
            depositAmount,
            uint16(depositTokenName.length),
            depositTokenName,
            withdrawPool,
            withdrawUser,
            uint16(withdrawTokenName.length),
            withdrawTokenName,
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
        public
        pure
        returns (DepositAndWithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        DepositAndWithdrawPayload memory decodeData;

        dataLen = 20;
        decodeData.depositPool = payload.toAddress(index);
        index += dataLen;

        dataLen = 20;
        decodeData.depositUser = payload.toAddress(index);
        index += dataLen;

        dataLen = 8;
        decodeData.depositAmount = payload.toUint64(index);
        index += dataLen;

        dataLen = 2;
        uint16 depositTokenNameLength = payload.toUint16(index);
        index += dataLen;

        dataLen = depositTokenNameLength;
        decodeData.depositTokenName = payload.slice(index, dataLen);
        index += dataLen;

        dataLen = 20;
        decodeData.withdrawPool = payload.toAddress(index);
        index += dataLen;

        dataLen = 20;
        decodeData.withdrawUser = payload.toAddress(index);
        index += dataLen;

        dataLen = 2;
        uint16 withdrawTokenNameLength = payload.toUint16(index);
        index += dataLen;

        dataLen = withdrawTokenNameLength;
        decodeData.withdrawTokenName = payload.slice(index, dataLen);
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
        require(index == length, "Decode deposit and withdraw payload error");

        return decodeData;
    }
}
