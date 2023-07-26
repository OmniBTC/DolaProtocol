// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IWormholeAdapterPool.sol";
import "../libraries/LibSystemCodec.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";
import "../libraries/LibAsset.sol";

contract SystemPortal {
    uint8 public constant SYSTEM_APP_ID = 0;

    IWormholeAdapterPool public immutable wormholeAdapterPool;

    event RelayEvent(
        uint64 sequence,
        uint64 nonce,
        LibDolaTypes.DolaAddress dstPool,
        uint256 feeAmount,
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

    constructor(IWormholeAdapterPool _wormholeAdapterPool) {
        wormholeAdapterPool = _wormholeAdapterPool;
    }

    function binding(
        uint16 bindDolaChainId,
        bytes memory bindAddress,
        uint256 fee
    ) external payable {
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibSystemCodec.encodeBindPayload(
            bindDolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(bindDolaChainId, bindAddress),
            LibSystemCodec.BINDING
        );

        uint64 sequence = IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            SYSTEM_APP_ID,
            appPayload
        );

        address relayer = IWormholeAdapterPool(wormholeAdapterPool)
            .getOneRelayer(nonce);

        LibAsset.transferAsset(address(0), payable(relayer), fee);

        emit RelayEvent(
            sequence,
            nonce,
            LibDolaTypes.DolaAddress(dolaChainId, ""),
            fee,
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
        uint64 nonce = IWormholeAdapterPool(wormholeAdapterPool).getNonce();
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibSystemCodec.encodeBindPayload(
            unbindDolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(unbindDolaChainId, unbindAddress),
            LibSystemCodec.UNBINDING
        );

        uint64 sequence = IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            SYSTEM_APP_ID,
            appPayload
        );

        address relayer = IWormholeAdapterPool(wormholeAdapterPool)
            .getOneRelayer(nonce);

        LibAsset.transferAsset(address(0), payable(relayer), fee);

        emit RelayEvent(
            sequence,
            nonce,
            LibDolaTypes.DolaAddress(dolaChainId, ""),
            fee,
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
