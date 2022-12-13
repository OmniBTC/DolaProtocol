// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "../interfaces/IOmniPool.sol";

library LibPool {
    using LibBytes for bytes;

    bytes32 internal constant DIAMOND_STORAGE_POSITION =
        keccak256("omnibtc.dola.omnipool");

    struct Storage {
        mapping(bytes => address) omnipool;
    }

    struct SendDepositPayload {
        address pool;
        address user;
        uint64 amount;
        bytes tokenName;
        uint16 appId;
        bytes appPayload;
    }

    struct SendWithdrawPayload {
        address pool;
        address user;
        bytes tokenName;
        uint16 appId;
        bytes appPayload;
    }

    struct SendDepositAndWithdrawPayload {
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

    struct ReceiveWithdrawPayload {
        address pool;
        address user;
        uint64 amount;
        bytes tokenName;
    }

    function omnipool(bytes memory _tokenName)
        internal
        view
        returns (IOmniPool)
    {
        Storage storage ds = diamondStorage();
        return IOmniPool(ds.omnipool[_tokenName]);
    }

    function getPool(bytes memory _tokenName) internal view returns (address) {
        Storage storage ds = diamondStorage();
        return ds.omnipool[_tokenName];
    }

    function addPool(address _pool) internal {
        bytes memory tokenName = IOmniPool(_pool).getTokenName();
        Storage storage ds = diamondStorage();
        ds.omnipool[tokenName] = _pool;
    }

    function removePool(bytes memory _tokenName) internal {
        Storage storage ds = diamondStorage();
        ds.omnipool[_tokenName] = address(0);
    }

    function encodeSendDepositPayload(
        address pool,
        address user,
        uint64 amount,
        bytes memory tokenName,
        uint16 appId,
        bytes memory appPayload
    ) internal pure returns (bytes memory) {
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
        internal
        pure
        returns (SendDepositPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendDepositPayload memory decodeData;

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
        require(index == length, "Decode send deposit payload error");

        return decodeData;
    }

    function encodeSendWithdrawPayload(
        address pool,
        address user,
        bytes memory tokenName,
        uint16 appId,
        bytes memory appPayload
    ) internal pure returns (bytes memory) {
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
        internal
        pure
        returns (SendWithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendWithdrawPayload memory decodeData;

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
        require(index == length, "Decode send withdraw payload error");

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
    ) internal pure returns (bytes memory) {
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
        internal
        pure
        returns (SendDepositAndWithdrawPayload memory)
    {
        uint256 length = payload.length;
        uint256 index;
        uint256 dataLen;
        SendDepositAndWithdrawPayload memory decodeData;

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

        require(index == length, "Decode receive withdraw payload error");

        return decodeData;
    }

    function diamondStorage() internal pure returns (Storage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
