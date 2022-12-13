// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibWormhole.sol";
import "../../libraries/LibGovernance.sol";
import "../../libraries/LibDiamond.sol";
import "../../libraries/LibPool.sol";

contract GovernanceFacet {
    function receiveDiamondCut(bytes memory vaa) external {
        (IWormhole.VM memory vm, , ) = LibWormhole.wormhole().parseAndVerifyVM(
            vaa
        );
        require(
            LibGovernance.governanceChainId() == vm.emitterChainId,
            "not governance chain id"
        );
        require(
            LibGovernance.remoteGovernance() == vm.emitterAddress,
            "not governance emitter"
        );
        require(
            !LibGovernance.isConsumedAction(vm.hash),
            "action already executed"
        );
        LibGovernance.setActionConsumed(vm.hash);
        LibDiamond.diamondCutParams memory cutParams = LibDiamond
            .decodeDiamondCut(vm.payload);
        LibDiamond.diamondCut(
            cutParams._diamondCut,
            cutParams._init,
            cutParams._calldata
        );
    }

    function addPool(address pool) external {
        LibPool.addPool(pool);
    }
}
