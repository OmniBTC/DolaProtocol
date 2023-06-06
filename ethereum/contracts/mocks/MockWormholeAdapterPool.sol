// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../libraries/LibAsset.sol";
import "../libraries/LibPoolCodec.sol";
import "../libraries/LibLendingCodec.sol";
import "../libraries/LibSystemCodec.sol";
import "../omnipool/DolaPool.sol";
import "../../interfaces/IWormhole.sol";
import "../libraries/LibWormholeAdapterVerify.sol";

contract MockWormholeAdapterPool {
    /// Storage

    // Wormhole address
    IWormhole immutable wormhole;
    // Dola chain id
    uint16 public immutable dolaChainId;
    // Dola pool
    DolaPool immutable dolaPool;

    // Wormhole required number of block confirmations to assume finality
    uint8 wormholeFinality;
    // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
    mapping(uint16 => bytes32) registeredEmitters;
    // Used to verify that the VAA has been processed
    mapping(bytes32 => bool) consumedVaas;

    // todo! Delete after wormhole running
    mapping(uint32 => bytes) public cachedVAA;
    uint32 vaaNonce;

    event PoolWithdrawEvent(
        uint64 nonce,
        uint16 sourceChainId,
        uint16 dstChianId,
        bytes poolAddress,
        bytes receiver,
        uint64 amount
    );

    constructor(
        IWormhole _wormhole,
        uint16 _dolaChainId,
        uint8 _wormholeFinality
    ) {
        wormhole = _wormhole;
        dolaChainId = _dolaChainId;
        dolaPool = new DolaPool(_dolaChainId, address(this));
        wormholeFinality = _wormholeFinality;
    }

    // todo! Delete after wormhole running
    function getNonce() public view returns (uint32) {
        return vaaNonce;
    }

    function getLatestVAA() public view returns (bytes memory) {
        return cachedVAA[getNonce() - 1];
    }

    function increaseNonce() internal {
        vaaNonce += 1;
    }

    /// Call by governance

    function getDolaContract() public view returns (uint256) {
        return uint256(uint160(address(this)));
    }

    function registerSpender(bytes memory encodedVm) external {
        //        IWormhole.VM memory vaa = LibWormholeAdapterVerify
        //            .parseVerifyAndReplayProtect(
        //                wormhole,
        //                registeredEmitters,
        //                consumedVaas,
        //                encodedVm
        //            );
        LibPoolCodec.ManagePoolPayload memory payload = LibPoolCodec
            .decodeManagePoolPayload(encodedVm);
        require(
            payload.poolCallType == LibPoolCodec.POOL_REGISTER_SPENDER,
            "INVALID CALL TYPE"
        );
        require(payload.dolaChainId == dolaChainId, "INVALIE DOLA CHAIN");
        dolaPool.registerSpender(address(uint160(payload.dolaContract)));
    }

    function deleteSpender(bytes memory encodedVm) external {
        //        IWormhole.VM memory vaa = LibWormholeAdapterVerify
        //            .parseVerifyAndReplayProtect(
        //                wormhole,
        //                registeredEmitters,
        //                consumedVaas,
        //                encodedVm
        //            );
        LibPoolCodec.ManagePoolPayload memory payload = LibPoolCodec
            .decodeManagePoolPayload(encodedVm);
        require(
            payload.poolCallType == LibPoolCodec.POOL_DELETE_SPENDER,
            "INVALID CALL TYPE"
        );
        require(payload.dolaChainId == dolaChainId, "INVALIE DOLA CHAIN");
        dolaPool.deleteSpender(address(uint160(payload.dolaContract)));
    }

    /// Call by application

    /// Send deposit by application
    function sendDeposit(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.maxApproveERC20(IERC20(token), address(dolaPool), amount);
        }

        bytes memory payload = dolaPool.deposit{value: msg.value}(
            token,
            amount,
            appId,
            appPayload
        );

        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    /// Send message that do not involve incoming or outgoing funds by application
    function sendMessage(uint16 appId, bytes memory appPayload)
        external
        payable
    {
        bytes memory payload = dolaPool.sendMessage(appId, appPayload);
        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    /// Receive withdraw
    function receiveWithdraw(bytes memory encodedVm) public {
        //        IWormhole.VM memory vaa = LibWormholeAdapterVerify
        //            .parseVerifyAndReplayProtect(
        //                wormhole,
        //                registeredEmitters,
        //                consumedVaas,
        //                encodedVm
        //            );
        LibPoolCodec.WithdrawPayload memory payload = LibPoolCodec
            .decodeWithdrawPayload(encodedVm);
        dolaPool.withdraw(payload.user, payload.amount, payload.pool);

        emit PoolWithdrawEvent(
            payload.nonce,
            payload.sourceChainId,
            payload.pool.dolaChainId,
            payload.pool.externalAddress,
            payload.user.externalAddress,
            payload.amount
        );
    }
}
