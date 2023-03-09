// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

library LibWormholeAdapterVerify {
    function getRegisteredEmitter(
        mapping(uint16 => bytes32) storage registeredEmitters,
        uint16 chainId
    ) internal view returns (bytes32) {
        return registeredEmitters[chainId];
    }

    function assertKnownEmitter(
        mapping(uint16 => bytes32) storage registeredEmitters,
        IWormhole.VM memory vm
    ) internal view {
        bytes32 maybeEmitter = getRegisteredEmitter(
            registeredEmitters,
            vm.emitterChainId
        );
        require(maybeEmitter == vm.emitterAddress, "UNKNOWN EMITTER");
    }

    function parseAndVerify(
        IWormhole wormhole,
        mapping(uint16 => bytes32) storage registeredEmitters,
        bytes memory encodedVm
    ) internal view returns (IWormhole.VM memory) {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole
            .parseAndVerifyVM(encodedVm);
        require(valid, reason);
        assertKnownEmitter(registeredEmitters, vm);
        return vm;
    }

    function replayProtect(
        mapping(bytes32 => bool) storage consumedVaas,
        IWormhole.VM memory vm
    ) internal {
        require(!consumedVaas[vm.hash], "ALREADY COMPLETED");
        consumedVaas[vm.hash] = true;
    }

    function parseVerifyAndReplayProtect(
        IWormhole wormhole,
        mapping(uint16 => bytes32) storage registeredEmitters,
        mapping(bytes32 => bool) storage consumedVaas,
        bytes memory encodedVm
    ) internal returns (IWormhole.VM memory) {
        IWormhole.VM memory vm = parseAndVerify(
            wormhole,
            registeredEmitters,
            encodedVm
        );
        replayProtect(consumedVaas, vm);
        return vm;
    }
}
