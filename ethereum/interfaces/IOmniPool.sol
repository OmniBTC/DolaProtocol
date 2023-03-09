// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IOmniPool {
    function decimals(address token) external view returns (uint8);

    function rely(address bridge) external;

    function deny(address bridge) external;

    function deposit(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);

    function withdrawTo(
        bytes memory token,
        uint16 appId,
        bytes memory appPayload
    ) external view returns (bytes memory);

    function withdraw(
        address token,
        address to,
        uint64 amount
    ) external;

    function depositAndWithdraw(
        address depositToken,
        uint256 depositAmount,
        uint16 withdrawChainId,
        bytes memory withdrawToken,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);
}
