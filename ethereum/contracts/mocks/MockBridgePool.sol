// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries//LibPool.sol";
import "../libraries//LibBinding.sol";
import "../../interfaces/IPoolOwner.sol";
import "../../interfaces/IWormhole.sol";

contract MockBridgePool {
    address public wormholeBridge;
    uint32 public nonce;
    uint16 public dolaChainId;
    uint16 public wormholeChainId;
    uint8 public finality;
    address public remoteBridge;
    address public poolOwner;
    bool public poolInit;
    mapping(bytes32 => bool) public completeVAA;
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

    /// @dev Only the first bridge pool needs this
    function initPool(address pool) external {
        require(!poolInit, "Pool has been initialized!");
        poolOwner = pool;
        poolInit = true;
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

    function sendUnbinding() external payable {
        bytes memory payload = LibBinding.encodeUnbindingPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender)
        );
        cachedVAA[getNonce()] = payload;

        increaseNonce();
    }

    function sendDeposit(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload;
        if (
            IPoolOwner(poolOwner).token(pool) == address(0) &&
            msg.value >= amount
        ) {
            payload = IPoolOwner(poolOwner).depositTo{value: amount}(
                pool,
                amount,
                appId,
                appPayload
            );
        } else {
            payload = IPoolOwner(poolOwner).depositTo(
                pool,
                amount,
                appId,
                appPayload
            );
        }

        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function sendWithdraw(
        address pool,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = IPoolOwner(poolOwner).withdrawTo(
            pool,
            appId,
            appPayload
        );
        cachedVAA[getNonce()] = payload;
        increaseNonce();
    }

    function sendDepositAndWithdraw(
        address depositPool,
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload;
        if (
            IPoolOwner(poolOwner).token(depositPool) == address(0) &&
            msg.value >= depositAmount
        ) {
            payload = IPoolOwner(poolOwner).depositAndWithdraw{
                value: depositAmount
            }(depositPool, depositAmount, withdrawPool, appId, appPayload);
        } else {
            payload = IPoolOwner(poolOwner).depositAndWithdraw(
                depositPool,
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
        address pool = LibDolaTypes.dolaAddressToAddress(payload.pool);
        address user = LibDolaTypes.dolaAddressToAddress(payload.user);
        IPoolOwner(poolOwner).innerWithdraw(pool, user, payload.amount);
    }
}
