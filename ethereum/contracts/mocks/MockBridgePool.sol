// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries//LibPool.sol";
import "../libraries//LibBinding.sol";
import "../../interfaces/IOmniPool.sol";
import "../../interfaces/IWormhole.sol";

contract MockBridgePool {
    address wormholeBridge;
    uint32 nonce;
    uint16 dolaChainId;
    uint16 wormholeChainId;
    uint8 finality;
    address remoteBridge;
    address deployer;
    address omnipool;
    bool hasInit;
    mapping(bytes32 => bool) completeVAA;
    // convenient for testing
    mapping(uint32 => bytes) public cachedVAA;

    constructor(
        address _wormholeBridge,
        uint16 _dolaChainId,
        uint16 _wormholeChainId,
        uint8 _finality,
        address _remoteBridge
    ) {
        wormholeBridge = _wormholeBridge;
        dolaChainId = _dolaChainId;
        wormholeChainId = _wormholeChainId;
        finality = _finality;
        remoteBridge = _remoteBridge;
        deployer = msg.sender;
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
        return nonce;
    }

    function getFinality() public view returns (uint8) {
        return finality;
    }

    function getLatestVAA() public view returns (bytes memory) {
        return cachedVAA[getNonce() - 1];
    }

    function increaseNonce() internal {
        nonce += 1;
    }

    function setVAAComplete(bytes32 _hash) internal {
        completeVAA[_hash] = true;
    }

    function isCompleteVAA(bytes32 _hash) internal view returns (bool) {
        return completeVAA[_hash];
    }

    function initOmniPool(address _omnipool) external {
        require(msg.sender == deployer, "Must be deployer!");
        require(!hasInit, "Only init one time!");
        omnipool = _omnipool;
    }

    function sendBinding(uint16 bindDolaChainId, bytes memory bindAddress)
        external
        payable
    {
        bytes memory payload = LibBinding.encodeBindingPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            LibDolaTypes.DolaAddress(bindDolaChainId, bindAddress)
        );
        cachedVAA[getNonce()] = payload;

        increaseNonce();
    }

    function sendUnbinding(uint16 unbindDolaChainId, bytes memory unbindAddress)
        external
        payable
    {
        bytes memory payload = LibBinding.encodeUnbindingPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
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
        if (token == address(0) && msg.value >= amount) {
            payload = IOmniPool(omnipool).depositTo{value: amount}(
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
        address token,
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
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload;
        if (depositToken == address(0) && msg.value >= depositAmount) {
            payload = IOmniPool(omnipool).depositAndWithdraw{
                value: depositAmount
            }(depositToken, depositAmount, withdrawPool, appId, appPayload);
        } else {
            payload = IOmniPool(omnipool).depositAndWithdraw(
                depositToken,
                depositAmount,
                withdrawPool,
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
    }
}
