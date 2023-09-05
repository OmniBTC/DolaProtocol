// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBoolAdapterPool {
    function dolaChainId() external view returns (uint16);

    function getNonce() external returns (uint64);

    function getOneRelayer(uint64 nonce) external view returns (address);

    function sendDeposit(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes32);

    function sendMessage(
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes32);
}
