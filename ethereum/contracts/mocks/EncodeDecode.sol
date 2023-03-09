// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries//LibDolaTypes.sol";
import "../libraries//LibLending.sol";
import "../libraries//LibPoolCodec.sol";

contract EncodeDecode {
    function encodeDepositPayload(
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return
            LibPoolCodec.encodeDepositPayload(
                pool,
                user,
                amount,
                appId,
                appPayload
            );
    }

    function decodeDepositPayload(bytes memory payload)
        external
        pure
        returns (LibPoolCodec.DepositPayload memory)
    {
        return LibPoolCodec.decodeDepositPayload(payload);
    }

    function encodeSendMessagePayload(
        LibDolaTypes.DolaAddress memory user,
        uint16 appId,
        bytes memory appPayload
    ) external pure returns (bytes memory) {
        return LibPoolCodec.encodeSendMessagePayload(user, appId, appPayload);
    }

    function decodeSendMessagePayload(bytes memory payload)
        external
        pure
        returns (LibPoolCodec.SendMessagePayload memory)
    {
        return LibPoolCodec.decodeSendMessagePayload(payload);
    }

    function encodeWithdrawPayload(
        uint16 sourceChainId,
        uint64 nonce,
        LibDolaTypes.DolaAddress memory pool,
        LibDolaTypes.DolaAddress memory user,
        uint64 amount
    ) external pure returns (bytes memory) {
        return
            LibPoolCodec.encodeWithdrawPayload(
                sourceChainId,
                nonce,
                pool,
                user,
                amount
            );
    }

    function decodeWithdrawPayload(bytes memory payload)
        external
        pure
        returns (LibPoolCodec.WithdrawPayload memory)
    {
        return LibPoolCodec.decodeWithdrawPayload(payload);
    }

    function encodeLendingAppPayload(
        uint16 sourceChainId,
        uint64 nonce,
        uint8 callType,
        uint64 amount,
        LibDolaTypes.DolaAddress memory receiver,
        uint64 liquidateUserId
    ) external pure returns (bytes memory) {
        return
            LibLending.encodeLendingAppPayload(
                sourceChainId,
                nonce,
                callType,
                amount,
                receiver,
                liquidateUserId
            );
    }

    function decodeLendingAppPayload(bytes memory payload)
        external
        pure
        returns (LibLending.LendingAppPayload memory)
    {
        return LibLending.decodeLendingAppPayload(payload);
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
