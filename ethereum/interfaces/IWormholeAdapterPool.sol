// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeAdapterPool {
    function dolaChainId() external view returns (uint16);

    function getNonce() external view returns (uint64);

    function sendDeposit(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendMessage(
        uint16 appId,
        bytes memory appPayload
    ) external;
}
