// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";
import "../interfaces/IOmniPool.sol";

library LibWormhole {
    bytes32 internal constant DIAMOND_STORAGE_POSITION =
        keccak256("omnibtc.dola.wormhole");

    struct Storage {
        address wormholeBridge;
        // todo: fix multiple pools
        mapping(bytes => address) omnipool;
        uint32 nonce;
        uint16 chainId;
        uint8 finality;
        address remoteBridge;
        mapping(bytes32 => bool) completeVAA;
    }

    function wormholeMessageFee() internal view returns (uint256) {
        Storage storage ds = diamondStorage();
        return IWormhole(ds.wormholeBridge).messageFee();
    }

    function wormhole() internal view returns (IWormhole) {
        Storage storage ds = diamondStorage();
        return IWormhole(ds.wormholeBridge);
    }

    function nonce() internal view returns (uint32) {
        Storage storage ds = diamondStorage();
        return ds.nonce;
    }

    function finality() internal view returns (uint8) {
        Storage storage ds = diamondStorage();
        return ds.finality;
    }

    function omnipool(bytes memory tokenName)
        internal
        view
        returns (IOmniPool)
    {
        Storage storage ds = diamondStorage();
        return IOmniPool(ds.omnipool[tokenName]);
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

    function addPool(bytes memory _tokenName, address _pool) internal {
        Storage storage ds = diamondStorage();
        ds.omnipool[_tokenName] = _pool;
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
