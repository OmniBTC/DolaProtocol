// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/LibPool.sol";
import "../libraries/LibProtocol.sol";
import "../../interfaces/IOmniPool.sol";
import "../../interfaces/IWormhole.sol";

contract MockBridgePool {
    address wormholeBridge;
    uint32 vaaNonce;
    uint16 dolaChainId;
    uint16 wormholeChainId;
    uint8 finality;
    address remoteBridge;
    address omnipool;
    mapping(bytes32 => bool) completeVAA;
    // convenient for testing
    mapping(uint32 => bytes) public cachedVAA;

    event PoolWithdrawEvent(uint64 nonce, uint16 sourceChainId, uint16 dstChianId, bytes poolAddress, bytes receiver, uint64 amount);

    constructor(
        address _wormholeBridge,
        uint16 _dolaChainId,
        uint16 _wormholeChainId,
        uint8 _finality,
        address _remoteBridge,
        address _omnipool
    ) {
        wormholeBridge = _wormholeBridge;
        dolaChainId = _dolaChainId;
        wormholeChainId = _wormholeChainId;
        finality = _finality;
        remoteBridge = _remoteBridge;
        omnipool = _omnipool;
    }

    function wormhole() public view returns (IWormhole) {
        return IWormhole(wormholeBridge);
    }

    function getWormholeMessageFee() public view returns (uint256) {
        return IWormhole(wormholeBridge).messageFee();
    }

    function getWormholeBridge() public view returns (address) {
        return wormholeBridge;
    }

    function getNonce() public view returns (uint32) {
        return vaaNonce;
    }

    function getFinality() public view returns (uint8) {
        return finality;
    }

    function getLatestVAA() public view returns (bytes memory) {
        return cachedVAA[getNonce() - 1];
    }

    function increaseNonce() internal {
        vaaNonce += 1;
    }

    function setVAAComplete(bytes32 _hash) internal {
        completeVAA[_hash] = true;
    }

    function isCompleteVAA(bytes32 _hash) internal view returns (bool) {
        return completeVAA[_hash];
    }

    function sendBinding(uint64 nonce, uint8 callType, uint16 bindDolaChainId, bytes memory bindAddress)
    external
    payable
    {
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

    function sendUnbinding(uint64 nonce, uint8 callType, uint16 unbindDolaChainId, bytes memory unbindAddress)
    external
    payable
    {
        bytes memory payload = LibProtocol.encodeProtocolAppPayload(
            dolaChainId,
            nonce,
            callType,
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDolaTypes.DolaAddress(unbindDolaChainId, unbindAddress)
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
            payload = IOmniPool(omnipool).depositTo{value : amount}(
                token,
                amount,
                appId,
                appPayload
            );
        } else {
            payload = IOmniPool(omnipool).depositTo(
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
        bytes memory payload = IOmniPool(omnipool).withdrawTo(
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
            payload = IOmniPool(omnipool).depositAndWithdraw{
            value : depositAmount
            }(depositToken, depositAmount, withdrawChainId, withdrawToken, appId, appPayload);
        } else {
            payload = IOmniPool(omnipool).depositAndWithdraw(
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
        IOmniPool(omnipool).innerWithdraw(token, user, payload.amount);
        emit PoolWithdrawEvent(payload.nonce, payload.sourceChainId, payload.pool.dolaChainId, payload.pool.externalAddress, payload.user.externalAddress, payload.amount);
    }
}
