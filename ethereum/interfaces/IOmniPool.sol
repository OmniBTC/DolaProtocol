// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IOmniPool {
    function decimals() external view returns (uint8);

    function getTokenName() external view returns (bytes memory);

    function getTokenAddress() external view returns (address);

    function rely(address bridge) external;

    function deny(address bridge) external;

    function depositTo(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external returns (bytes memory);

    function withdrawTo(uint16 appId, bytes memory appPayload)
        external
        view
        returns (bytes memory);

    function innerWithdraw(address to, uint64 amount) external;

    function depositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) external returns (bytes memory);
}
