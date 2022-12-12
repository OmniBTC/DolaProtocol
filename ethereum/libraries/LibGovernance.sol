// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library LibGovernance {
    bytes32 internal constant DIAMOND_STORAGE_POSITION =
        keccak256("omnibtc.dola.governance");

    struct Storage {
        uint16 governanceChainId;
        bytes32 remoteGovernance;
        mapping(bytes32 => bool) consumedGovernanceActions;
    }

    function initGovernance(
        uint16 _governanceChainId,
        bytes32 _remoteGovernance
    ) internal {
        Storage storage ds = diamondStorage();
        ds.governanceChainId = _governanceChainId;
        ds.remoteGovernance = _remoteGovernance;
    }

    function governanceChainId() internal view returns (uint16) {
        Storage storage ds = diamondStorage();
        return ds.governanceChainId;
    }

    function remoteGovernance() internal view returns (bytes32) {
        Storage storage ds = diamondStorage();
        return ds.remoteGovernance;
    }

    function setActionConsumed(bytes32 _hash) internal {
        Storage storage ds = diamondStorage();
        ds.consumedGovernanceActions[_hash] = true;
    }

    function isConsumedAction(bytes32 _hash) internal view returns (bool) {
        Storage storage ds = diamondStorage();
        return ds.consumedGovernanceActions[_hash];
    }

    function diamondStorage() internal pure returns (Storage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
