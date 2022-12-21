// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibPool.sol";
import "../../libraries/LibBinding.sol";
import "../../interfaces/IOmniPool.sol";
import "../../interfaces/IWormhole.sol";

contract BridgePool {
    address wormholeBridge;
    uint32 nonce;
    uint16 dolaChainId;
    uint16 wormholeChainId;
    uint8 finality;
    address remoteBridge;
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

    function sendBinding(uint16 bindDolaChainId, bytes memory bindAddress)
        external
        payable
    {
        bytes memory payload = LibBinding.encodeBindingPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, msg.sender),
            LibDolaTypes.DolaAddress(bindDolaChainId, bindAddress)
        );
        cachedVAA[getNonce()] = payload;
        wormhole().publishMessage{value: msg.value}(
            getNonce(),
            payload,
            getFinality()
        );
        increaseNonce();
    }

    function sendDeposit(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = IOmniPool(pool).depositTo(
            amount,
            appId,
            appPayload
        );
        cachedVAA[getNonce()] = payload;
        wormhole().publishMessage{value: msg.value}(
            getNonce(),
            payload,
            getFinality()
        );
        increaseNonce();
    }

    function sendWithdraw(
        address pool,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = IOmniPool(pool).withdrawTo(appId, appPayload);
        cachedVAA[getNonce()] = payload;
        IWormhole(wormhole()).publishMessage{value: msg.value}(
            getNonce(),
            payload,
            getFinality()
        );
        increaseNonce();
    }

    function sendDepositAndWithdraw(
        address depositPool,
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = IOmniPool(depositPool).depositAndWithdraw(
            depositAmount,
            withdrawPool,
            appId,
            appPayload
        );
        cachedVAA[getNonce()] = payload;
        IWormhole(wormhole()).publishMessage{value: msg.value}(
            getNonce(),
            payload,
            getFinality()
        );
        increaseNonce();
    }

    function receiveWithdraw(bytes memory vaa) public {
        // todo: use this when more formal
        // (IWormhole.VM memory vm, , ) = wormhole().parseAndVerifyVM(vaa);
        // require(!isCompleteVAA(vm.hash), "withdraw already completed");
        // setVAAComplete(vm.hash);
        // LibPool.ReceiveWithdrawPayload memory payload = LibPool
        //     .decodeReceiveWithdrawPayload(vm.payload);

        LibPool.ReceiveWithdrawPayload memory payload = LibPool
            .decodeReceiveWithdrawPayload(vaa);
        address pool = LibDolaTypes.dolaAddressToAddress(payload.pool);
        address user = LibDolaTypes.dolaAddressToAddress(payload.user);
        IOmniPool(pool).innerWithdraw(user, payload.amount);
    }
}
