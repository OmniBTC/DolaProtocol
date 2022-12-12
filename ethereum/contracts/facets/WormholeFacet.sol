// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibDiamond.sol";
import "../../libraries/LibPool.sol";
import "../../interfaces/IWormhole.sol";
import "../../interfaces/IOmniPool.sol";

contract WormholeFacet {
    bytes32 internal constant DIAMOND_STORAGE_POSITION =
        keccak256("omnibtc.dola.facets.wormhole");

    struct Storage {
        address wormhole;
        address omnipool;
        uint32 nonce;
        uint16 chainId;
        uint8 finality;
        address remoteBridge;
        mapping(bytes32 => bool) completeVAA;
    }

    function initWormhole(
        address wormhole,
        uint16 chainId,
        uint8 finality,
        address bridge
    ) external {
        LibDiamond.enforceIsContractOwner();
        Storage storage ds = diamondStorage();
        ds.wormhole = wormhole;
        ds.chainId = chainId;
        ds.finality = finality;
        ds.remoteBridge = bridge;
    }

    function sendDeposit(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        Storage storage ds = diamondStorage();

        bytes memory payload = IOmniPool(ds.omnipool).depositTo(
            amount,
            appId,
            appPayload
        );
        // todo: fix eth
        IWormhole(ds.wormhole).publishMessage{value: msg.value}(
            ds.nonce,
            payload,
            ds.finality
        );
        ds.nonce += 1;
    }

    function sendWithdraw(uint16 appId, bytes memory appPayload)
        external
        payable
    {
        Storage storage ds = diamondStorage();

        bytes memory payload = IOmniPool(ds.omnipool).withdrawTo(
            appId,
            appPayload
        );
        IWormhole(ds.wormhole).publishMessage{value: msg.value}(
            ds.nonce,
            payload,
            ds.finality
        );
        ds.nonce += 1;
    }

    function sendDepositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        Storage storage ds = diamondStorage();

        bytes memory payload = IOmniPool(ds.omnipool).depositAndWithdraw(
            depositAmount,
            withdrawPool,
            withdrawUser,
            withdrawTokenName,
            appId,
            appPayload
        );
        IWormhole(ds.wormhole).publishMessage{value: msg.value}(
            ds.nonce,
            payload,
            ds.finality
        );
        ds.nonce += 1;
    }

    function receiveWithdraw(bytes memory vaa) public {
        Storage storage ds = diamondStorage();
        (IWormhole.VM memory vm, , ) = IWormhole(ds.wormhole).parseAndVerifyVM(
            vaa
        );
        require(!isCompleteVAA(vm.hash), "withdraw already completed");
        setVAAComplete(vm.hash);

        LibPool.ReceiveWithdrawPayload memory payload = LibPool
            .decodeReceiveWithdrawPayload(vm.payload);
        IOmniPool(ds.omnipool).innerWithdraw(payload.user, payload.amount);
    }

    function wormholeMessageFee() public view returns (uint256) {
        Storage storage ds = diamondStorage();
        return IWormhole(ds.wormhole).messageFee();
    }

    function setVAAComplete(bytes32 hash) internal {
        Storage storage ds = diamondStorage();
        ds.completeVAA[hash] = true;
    }

    function isCompleteVAA(bytes32 hash) public view returns (bool) {
        Storage storage ds = diamondStorage();
        return ds.completeVAA[hash];
    }

    function diamondStorage() internal pure returns (Storage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
