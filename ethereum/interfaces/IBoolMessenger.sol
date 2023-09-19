// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBoolMessenger {
    function cptTotalFee(
        address srcAnchor,
        uint32 dstChainId,
        uint32 payloadSize,
        bytes32 crossType,
        bytes memory extraFeed
    ) external view returns (uint256 feeInNative);
}