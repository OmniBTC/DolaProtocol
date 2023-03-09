// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/LibPool.sol";
import "../libraries/LibLending.sol";
import "../libraries/LibProtocol.sol";
import "./SinglePool.sol";
import "../../interfaces/IWormhole.sol";

contract WormholeAdapterPool {

    /// Storage

    // Wormhole address
    IWormhole immutable wormhole;
    // Dola chain id
    uint16 immutable dolaChainId;
    // Single pool
    SinglePool immutable singlePool;

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
        uint16 _dolaChainId
    ) {
        wormhole = _wormhole;
        dolaChainId = _dolaChainId;
        singlePool = new SinglePool(_dolaChainId, address(this));
    }

    function getWormholeMessageFee() public view returns (uint256) {
        return wormhole.messageFee();
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
        bytes memory payload;
        if (token == address(0)) {
            require(msg.value >= amount, "Not enough msg value!");
            payload = singlePool.depositTo{value : amount}(
                token,
                amount,
                appId,
                appPayload
            );
        } else {
            payload = singlePool.depositTo(
                token,
                amount,
                appId,
                appPayload
            );
        }

        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function sendWithdraw(
        bytes memory token,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = singlePool.withdrawTo(
            token,
            appId,
            appPayload
        );
        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function sendDepositAndWithdraw(
        address depositToken,
        uint256 depositAmount,
        uint16 withdrawChainId,
        bytes memory withdrawToken,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload;
        if (depositToken == address(0)) {
            require(msg.value >= depositAmount, "Not enough msg value!");
            payload = singlePool.depositAndWithdraw{
            value : depositAmount
            }(
                depositToken,
                depositAmount,
                withdrawChainId,
                withdrawToken,
                appId,
                appPayload
            );
        } else {
            payload = singlePool.depositAndWithdraw(
                depositToken,
                depositAmount,
                withdrawChainId,
                withdrawToken,
                appId,
                appPayload
            );
        }

        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function receiveWithdraw(bytes memory vaa) public {
        LibPool.ReceiveWithdrawPayload memory payload = LibPool
        .decodeReceiveWithdrawPayload(vaa);
        address token = LibDolaTypes.dolaAddressToAddress(payload.pool);
        address user = LibDolaTypes.dolaAddressToAddress(payload.user);
        singlePool.innerWithdraw(token, user, payload.amount);
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
