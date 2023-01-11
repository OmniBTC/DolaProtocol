// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IOmniPool {
    function token() external view returns (address);

    function decimals() external view returns (uint8);

    function depositTo(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);

    function withdrawTo(uint16 appId, bytes memory appPayload)
        external
        view
        returns (bytes memory);

    function innerWithdraw(address to, uint64 amount) external;

    function depositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes memory);
}
