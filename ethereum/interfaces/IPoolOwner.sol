// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IPoolOwner {
    function rely(address bridge) external;

    function deny(address bridge) external;

    function token(address pool) external view returns (address);

    function decimals(address pool) external view returns (uint8);

    function depositTo(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);

    function withdrawTo(
        address pool,
        uint16 appId,
        bytes memory appPayload
    ) external view returns (bytes memory);

    function innerWithdraw(
        address pool,
        address to,
        uint64 amount
    ) external;

    function depositAndWithdraw(
        address pool,
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);
}
