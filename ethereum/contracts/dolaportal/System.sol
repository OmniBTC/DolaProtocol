// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IWormholeAdapterPool.sol";
import "../libraries/LibSystemCodec.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";
import "../libraries/LibAsset.sol";

contract SystemPortal {
    uint8 public constant SYSTEM_APP_ID = 0;

    IWormholeAdapterPool immutable wormholeAdapterPool;
    uint64 public dolaNonce;
    address payable public relayer;

    event RelayEvent(uint32 nonce, uint256 amount);

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
        relayer = payable(msg.sender);
    }

    function getNonce() internal returns (uint64) {
        uint64 nonce = dolaNonce;
        dolaNonce++;
        return nonce;
    }

    function binding(
        uint16 bindDolaChainId,
        bytes memory bindAddress,
        uint256 fee
    ) external payable {
        uint64 nonce = getNonce();
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibSystemCodec.encodeBindPayload(
            bindDolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(dolaChainId, bindAddress),
            LibSystemCodec.BINDING
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            SYSTEM_APP_ID,
            appPayload
        );

        relayer.transfer(fee);

        emit RelayEvent(
            IWormholeAdapterPool(wormholeAdapterPool).getNonce() - 1,
            fee
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
        uint64 nonce = getNonce();
        uint16 dolaChainId = wormholeAdapterPool.dolaChainId();

        bytes memory appPayload = LibSystemCodec.encodeBindPayload(
            unbindDolaChainId,
            nonce,
            LibDolaTypes.DolaAddress(dolaChainId, unbindAddress),
            LibSystemCodec.UNBINDING
        );
        IWormholeAdapterPool(wormholeAdapterPool).sendMessage(
            SYSTEM_APP_ID,
            appPayload
        );

        relayer.transfer(fee);

        emit RelayEvent(
            IWormholeAdapterPool(wormholeAdapterPool).getNonce() - 1,
            fee
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
