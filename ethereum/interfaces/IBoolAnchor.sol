// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBoolAnchor {
    function messenger() external view returns (address);

    function sendToMessenger(
        address payable refundAddress,
        bytes32 crossType,
        bytes memory extraFeed,
        uint32 dstChainId,
        bytes calldata payload
    ) external payable returns (bytes32 txUniqueIdentification);
}