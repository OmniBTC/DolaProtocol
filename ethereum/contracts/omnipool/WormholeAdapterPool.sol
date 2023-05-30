// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../libraries/LibAsset.sol";
import "../libraries/LibPoolCodec.sol";
import "../libraries/LibLendingCodec.sol";
import "../libraries/LibSystemCodec.sol";
import "./DolaPool.sol";
import "../../interfaces/IWormhole.sol";
import "../libraries/LibWormholeAdapterVerify.sol";

contract WormholeAdapterPool {
    /// Storage

    // Wormhole address
    IWormhole public immutable wormhole;
    // Dola chain id
    uint16 public immutable dolaChainId;
    // Dola pool
    DolaPool public immutable dolaPool;

    // Wormhole required number of block confirmations to assume finality
    uint8 public wormholeInstantConsistency;
    uint8 public wormholeFinalityConsistency;
    // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
    mapping(uint16 => bytes32) public registeredEmitters;
    // Used to verify that the VAA has been processed
    mapping(bytes32 => bool) public consumedVaas;

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
        uint8 _wormholeInstantConsistency,
        uint8 _wormholeFinalityConsistency,
        uint16 _emitterChainId,
        bytes32 _emitterAddress
    ) {
        wormhole = _wormhole;
        dolaChainId = _dolaChainId;
        // First deploy pool
        dolaPool = new DolaPool(_dolaChainId, address(this));
        // Upgrade
        // dolaPool = _dolaPool;
        wormholeInstantConsistency = _wormholeInstantConsistency;
        wormholeFinalityConsistency = _wormholeFinalityConsistency;
        registeredEmitters[_emitterChainId] = _emitterAddress;
    }

    /// Call by governance

    function getDolaContract() public view returns (uint256) {
        return uint256(uint160(address(this)));
    }

    function registerSpender(bytes memory encodedVm) external {
        IWormhole.VM memory vaa = LibWormholeAdapterVerify
            .parseVerifyAndReplayProtect(
                wormhole,
                registeredEmitters,
                consumedVaas,
                encodedVm
            );
        LibPoolCodec.ManagePoolPayload memory payload = LibPoolCodec
            .decodeManagePoolPayload(vaa.payload);
        require(
            payload.poolCallType == LibPoolCodec.POOL_REGISTER_SPENDER,
            "INVALID CALL TYPE"
        );
        require(payload.dolaChainId == dolaChainId, "INVALIE DOLA CHAIN");
        dolaPool.registerSpender(address(uint160(payload.dolaContract)));
    }

    function deleteSpender(bytes memory encodedVm) external {
        /// @notice To prevent the pool from locking up
        require(dolaPool.spendersLength() > 1, "CANNOT DELETE LAST SPENDER");
        IWormhole.VM memory vaa = LibWormholeAdapterVerify
            .parseVerifyAndReplayProtect(
                wormhole,
                registeredEmitters,
                consumedVaas,
                encodedVm
            );
        LibPoolCodec.ManagePoolPayload memory payload = LibPoolCodec
            .decodeManagePoolPayload(vaa.payload);
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
    ) external payable returns (uint64) {
        uint256 wormholeFee = wormhole.messageFee();
        require(msg.value >= wormholeFee, "FEE NOT ENOUGH");
        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.maxApproveERC20(IERC20(token), address(dolaPool), amount);
        }

        bytes memory payload = dolaPool.deposit{value: msg.value - wormholeFee}(
            token,
            amount,
            appId,
            appPayload
        );
        return
            wormhole.publishMessage{value: wormholeFee}(
                0,
                payload,
                wormholeFinalityConsistency
            );
    }

    /// Send message that do not involve incoming or outgoing funds by application
    function sendMessage(uint16 appId, bytes memory appPayload)
        external
        payable
        returns (uint64)
    {
        uint256 wormholeFee = wormhole.messageFee();
        require(msg.value >= wormholeFee, "FEE NOT ENOUGH");
        bytes memory payload = dolaPool.sendMessage(appId, appPayload);
        return
            wormhole.publishMessage{value: msg.value}(
                0,
                payload,
                wormholeInstantConsistency
            );
    }

    /// Receive withdraw
    function receiveWithdraw(bytes memory encodedVm) public {
        IWormhole.VM memory vaa = LibWormholeAdapterVerify
            .parseVerifyAndReplayProtect(
                wormhole,
                registeredEmitters,
                consumedVaas,
                encodedVm
            );
        LibPoolCodec.WithdrawPayload memory payload = LibPoolCodec
            .decodeWithdrawPayload(vaa.payload);
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

    function getNonce() external returns (uint64) {
        return dolaPool.getNonce();
    }
}
