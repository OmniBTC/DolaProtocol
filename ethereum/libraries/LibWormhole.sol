// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";

library LibWormhole {
    bytes32 internal constant DIAMOND_STORAGE_POSITION =
        keccak256("omnibtc.dola.wormhole");

    struct Storage {
        address wormholeBridge;
        uint32 nonce;
        uint16 chainId;
        uint8 finality;
        address remoteBridge;
        mapping(bytes32 => bool) completeVAA;
    }

    function wormhole() internal view returns (IWormhole) {
        Storage storage ds = diamondStorage();
        return IWormhole(ds.wormholeBridge);
    }

    function wormholeMessageFee() internal view returns (uint256) {
        Storage storage ds = diamondStorage();
        return IWormhole(ds.wormholeBridge).messageFee();
    }

    function wormholeBridge() internal view returns (address) {
        Storage storage ds = diamondStorage();
        return ds.wormholeBridge;
    }

    function nonce() internal view returns (uint32) {
        Storage storage ds = diamondStorage();
        return ds.nonce;
    }

    function finality() internal view returns (uint8) {
        Storage storage ds = diamondStorage();
        return ds.finality;
    }

    function initWormhole(
        address _wormholeBridge,
        uint16 _chainId,
        uint8 _finality,
        address _remoteBridge
    ) internal {
        Storage storage ds = diamondStorage();
        ds.wormholeBridge = _wormholeBridge;
        ds.chainId = _chainId;
        ds.finality = _finality;
        ds.remoteBridge = _remoteBridge;
    }

    function increaseNonce() internal {
        Storage storage ds = diamondStorage();
        ds.nonce += 1;
    }

    function setVAAComplete(bytes32 _hash) internal {
        Storage storage ds = diamondStorage();
        ds.completeVAA[_hash] = true;
    }

    function isCompleteVAA(bytes32 _hash) internal view returns (bool) {
        Storage storage ds = diamondStorage();
        return ds.completeVAA[_hash];
    }

    function diamondStorage() internal pure returns (Storage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
