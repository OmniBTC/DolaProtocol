// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IBoolAdapterPool.sol";
import "../libraries/LibBoolAdapterVerify.sol";
import "../libraries/LibSystemCodec.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";
import "../libraries/LibAsset.sol";

contract SystemPortalBool {
    uint8 public constant SYSTEM_APP_ID = 0;

    IBoolAdapterPool public immutable boolAdapterPool;

    event RelayEvent(
        uint64 sequence,
        uint64 nonce,
        uint256 feeAmount,
        uint16 appId,
        uint8 callType
    );

    event SystemPortalEvent(
        uint64 nonce,
        address sender,
        uint16 sourceChainId,
        uint16 userChainId,
        bytes userAddress,
        uint8 callType
    );

    constructor(IBoolAdapterPool _boolAdapterPool) {
        boolAdapterPool = _boolAdapterPool;
    }

    function binding(
        uint16 bindDolaChainId,
        bytes memory bindAddress,
        uint256 fee
    ) external payable {
        uint64 nonce = IBoolAdapterPool(boolAdapterPool).getNonce();
        uint16 dolaChainId = boolAdapterPool.dolaChainId();

        bytes memory appPayload = LibSystemCodec.encodeBindPayload(
            bindDolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(bindDolaChainId, bindAddress),
            LibSystemCodec.BINDING
        );

        appPayload = LibBoolAdapterVerify.remapping_opcode(
            appPayload,
            LibBoolAdapterVerify.SERVER_OPCODE_SYSTEM_BINDING
        );

        IBoolAdapterPool(boolAdapterPool).sendMessage{
                value: msg.value - fee
        }(SYSTEM_APP_ID, appPayload);

        address relayer = IBoolAdapterPool(boolAdapterPool)
            .getOneRelayer(nonce);

        LibAsset.transferAsset(address(0), payable(relayer), fee);

        emit RelayEvent(
            0,
            nonce,
            fee,
            SYSTEM_APP_ID,
            LibSystemCodec.BINDING
        );

        emit SystemPortalEvent(
            nonce,
            msg.sender,
            dolaChainId,
            bindDolaChainId,
            bindAddress,
            LibSystemCodec.BINDING
        );
    }

    function unbinding(
        uint16 unbindDolaChainId,
        bytes memory unbindAddress,
        uint256 fee
    ) external payable {
        uint64 nonce = IBoolAdapterPool(boolAdapterPool).getNonce();
        uint16 dolaChainId = boolAdapterPool.dolaChainId();

        bytes memory appPayload = LibSystemCodec.encodeBindPayload(
            unbindDolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(unbindDolaChainId, unbindAddress),
            LibSystemCodec.UNBINDING
        );

        appPayload = LibBoolAdapterVerify.remapping_opcode(
            appPayload,
            LibBoolAdapterVerify.SERVER_OPCODE_SYSTEM_UNBINDING
        );

        IBoolAdapterPool(boolAdapterPool).sendMessage{
                value: msg.value - fee
        }(SYSTEM_APP_ID, appPayload);

        address relayer = IBoolAdapterPool(boolAdapterPool)
            .getOneRelayer(nonce);

        LibAsset.transferAsset(address(0), payable(relayer), fee);

        emit RelayEvent(
            0,
            nonce,
            fee,
            SYSTEM_APP_ID,
            LibSystemCodec.UNBINDING
        );

        emit SystemPortalEvent(
            nonce,
            msg.sender,
            dolaChainId,
            unbindDolaChainId,
            unbindAddress,
            LibSystemCodec.UNBINDING
        );
    }
}
