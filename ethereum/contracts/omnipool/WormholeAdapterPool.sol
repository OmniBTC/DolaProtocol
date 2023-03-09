// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/LibPool.sol";
import "../libraries/LibLending.sol";
import "../libraries/LibProtocol.sol";
import "./DolaPool.sol";
import "../../interfaces/IWormhole.sol";

contract WormholeAdapterPool {

    /// Storage

    // Wormhole address
    IWormhole immutable wormhole;
    // Dola chain id
    uint16 immutable dolaChainId;
    // Dola pool
    DolaPool immutable dolaPool;

    // Wormhole required number of block confirmations to assume finality
    uint8 wormholeFinality;
    // Used to verify that (emitter_chain, wormhole_emitter_address) is correct
    mapping(uint16 => bytes32)  registeredEmitters;
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

    //    function registerOwner(
    //        bytes memory encodedVm
    //    )public{
    //
    //    }

    function sendLendingHelperPayload(
        uint16[] memory dolaPoolIds,
        uint8 callType
    ) external payable {
        bytes memory payload = LibLending.encodeAppHelperPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            dolaPoolIds,
            callType
        );
        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function sendProtocolPayload(
        uint64 nonce,
        uint8 callType,
        uint16 bindDolaChainId,
        bytes memory bindAddress
    ) external payable {
        bytes memory payload = LibProtocol.encodeProtocolAppPayload(
            dolaChainId,
            nonce,
            callType,
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDolaTypes.DolaAddress(bindDolaChainId, bindAddress)
        );
        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function sendDeposit(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        uint256 wormholeFee = wormhole.messageFee();
        require(msg.value >= wormholeFee, "FEE NOT ENOUGH");
        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);
        bytes memory payload = dolaPool.deposit{value : msg.value - wormholeFee}(
            token,
            amount,
            appId,
            appPayload
        );
        wormhole.publishMessage{value : wormholeFee}(0, payload, wormholeFinality);

        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    //    function sendWithdraw(
    //        bytes memory token,
    //        uint16 appId,
    //        bytes memory appPayload
    //    ) external payable {
    //        bytes memory payload = dolaPool.withdrawTo(
    //            token,
    //            appId,
    //            appPayload
    //        );
    //        cachedVAA[getNonce()] = payload;
    //        increaseNonce();
    //    }

    function receiveWithdraw(bytes memory vaa) public {
        LibPool.WithdrawPayload memory payload = LibPool
        .decodeWithdrawPayload(vaa);
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
