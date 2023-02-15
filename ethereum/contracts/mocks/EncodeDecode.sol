// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries//LibDolaTypes.sol";
import "../libraries//LibLending.sol";
import "../libraries//LibPool.sol";

contract EncodeDecode {
    function encodeSendDepositPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return
            LibPool.encodeSendDepositPayload(
                pool,
                user,
                amount,
                appId,
                appPayload
            );
    }

    function decodeSendDepositPayload(bytes memory payload)
        external
        pure
        returns (LibPool.SendDepositPayload memory)
    {
        return LibPool.decodeSendDepositPayload(payload);
    }

    function encodeSendWithdrawPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return LibPool.encodeSendWithdrawPayload(pool, user, appId, appPayload);
    }

    function decodeSendWithdrawPayload(bytes memory payload)
        external
        pure
        returns (LibPool.SendWithdrawPayload memory)
    {
        return LibPool.decodeSendWithdrawPayload(payload);
    }

    function encodeSendDepositAndWithdrawPayload(
        LibDolaTypes.DolaAddress memory depositPool,
        LibDolaTypes.DolaAddress memory depositUser,
        uint64 depositAmount,
        LibDolaTypes.DolaAddress memory withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return
            LibPool.encodeSendDepositAndWithdrawPayload(
                depositPool,
                depositUser,
                depositAmount,
                withdrawPool,
                appId,
                appPayload
            );
    }

    function decodeSendDepositAndWithdrawPayload(bytes memory payload)
        external
        pure
        returns (LibPool.SendDepositAndWithdrawPayload memory)
    {
        return LibPool.decodeSendDepositAndWithdrawPayload(payload);
    }

    function encodeReceiveWithdrawPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount
    ) external pure returns (bytes memory) {
        return LibPool.encodeReceiveWithdrawPayload(pool, user, amount);
    }

    function decodeReceiveWithdrawPayload(bytes memory payload)
        external
        pure
        returns (LibPool.ReceiveWithdrawPayload memory)
    {
        return LibPool.decodeReceiveWithdrawPayload(payload);
    }

    function encodeAppPayload(
        uint64 nonce,
        uint8 callType,
        uint64 amount,
        LibDolaTypes.DolaAddress memory receiver,
        uint64 liquidateUserId
    ) external pure returns (bytes memory) {
        return
            LibLending.encodeAppPayload(
                nonce,
                callType,
                amount,
                receiver,
                liquidateUserId
            );
    }

    function decodeAppPayload(bytes memory payload)
        external
        pure
        returns (LibLending.LendingAppPayload memory)
    {
        return LibLending.decodeAppPayload(payload);
    }

    function encodeDolaAddress(uint16 dolaChainId, bytes memory externalAddress)
        external
        pure
        returns (bytes memory)
    {
        return LibDolaTypes.encodeDolaAddress(dolaChainId, externalAddress);
    }

    function decodeDolaAddress(bytes memory payload)
        external
        pure
        returns (LibDolaTypes.DolaAddress memory)
    {
        return LibDolaTypes.decodeDolaAddress(payload);
    }
}
