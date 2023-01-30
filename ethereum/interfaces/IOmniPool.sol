// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IOmniPool {
    function decimals(address token) external view returns (uint8);

    function rely(address bridge) external;

    function deny(address bridge) external;

    function depositTo(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);

    function withdrawTo(
        address token,
        uint16 appId,
        bytes memory appPayload
    ) external view returns (bytes memory);

    function innerWithdraw(
        address token,
        address to,
        uint64 amount
    ) external;

    function depositAndWithdraw(
        address depositToken,
        uint256 depositAmount,
        address withdrawToken,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);
}
