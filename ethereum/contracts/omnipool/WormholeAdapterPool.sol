// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../libraries/LibAsset.sol";
import "../libraries/LibPoolCodec.sol";
import "../libraries/LibLendingCodec.sol";
import "../libraries/LibSystemCodec.sol";
import "../libraries/LibGovCodec.sol";
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
    DolaPool public dolaPool;

    // Wormhole finality that does not involve funding
    uint8 public notInvolveFundConsistency;
    // Wormhole finality involving funding
    uint8 public involveFundConsistency;
    // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
    mapping(uint16 => bytes32) public registeredEmitters;
    // Used to verify that the VAA has been processed
    mapping(bytes32 => bool) public consumedVaas;
    // Used to verify relayer authority
    mapping(address => bool) public registeredRelayers;
    // Used to receive relayer fee
    address[] public relayers;

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
        DolaPool _dolaPool,
        uint8 _notInvolveFundConsistency,
        uint8 _involveFundConsistency,
        uint16 _emitterChainId,
        bytes32 _emitterAddress,
        address _initialRelayer
    ) {
        wormhole = _wormhole;
        dolaChainId = _dolaChainId;
        if (address(_dolaPool) == address(0x0)) {
            // First deploy pool
            dolaPool = new DolaPool(_dolaChainId, address(this));
        } else {
            // Upgrade
            dolaPool = _dolaPool;
        }

        notInvolveFundConsistency = _notInvolveFundConsistency;
        involveFundConsistency = _involveFundConsistency;
        registeredEmitters[_emitterChainId] = _emitterAddress;
        registeredRelayers[_initialRelayer] = true;
        relayers.push(_initialRelayer);
    }

    /// Modifiers

    modifier onlyRelayer() {
        require(registeredRelayers[msg.sender], "NOT RELAYER");
        _;
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

    function registerRelayer(bytes memory encodedVm) external {
        IWormhole.VM memory vaa = LibWormholeAdapterVerify
            .parseVerifyAndReplayProtect(
                wormhole,
                registeredEmitters,
                consumedVaas,
                encodedVm
            );
        LibGovCodec.RelayerPayload memory payload = LibGovCodec
            .decodeRelayerPayload(vaa.payload);

        require(payload.opcode == LibGovCodec.ADD_RELAYER_OPCODE);
        require(
            payload.relayer.dolaChainId == dolaChainId,
            "INVALIE DOLA CHAIN"
        );
        address relayer = LibDolaTypes.dolaAddressToAddress(payload.relayer);
        require(!registeredRelayers[relayer], "RELAYER ALREADY REGISTERED");
        registeredRelayers[relayer] = true;
        relayers.push(relayer);
    }

    function removeRelayer(bytes memory encodedVm) external {
        IWormhole.VM memory vaa = LibWormholeAdapterVerify
            .parseVerifyAndReplayProtect(
                wormhole,
                registeredEmitters,
                consumedVaas,
                encodedVm
            );
        LibGovCodec.RelayerPayload memory payload = LibGovCodec
            .decodeRelayerPayload(vaa.payload);

        require(payload.opcode == LibGovCodec.REMOVE_RELAYER_OPCODE);
        require(
            payload.relayer.dolaChainId == dolaChainId,
            "INVALIE DOLA CHAIN"
        );
        address relayer = LibDolaTypes.dolaAddressToAddress(payload.relayer);

        require(registeredRelayers[relayer], "RELAYER NOT REGISTERED");
        registeredRelayers[relayer] = false;
        for (uint256 i = 0; i < relayers.length; i++) {
            if (relayers[i] == relayer) {
                relayers[i] = relayers[relayers.length - 1];
                relayers.pop();
                break;
            }
        }
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
                involveFundConsistency
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
                notInvolveFundConsistency
            );
    }

    /// Receive withdraw
    function receiveWithdraw(bytes memory encodedVm) public onlyRelayer {
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

    function getOneRelayer(uint64 nonce) external view returns (address) {
        return relayers[nonce % relayers.length];
    }

    /// Get nonce
    function getNonce() external returns (uint64) {
        return dolaPool.getNonce();
    }
}
