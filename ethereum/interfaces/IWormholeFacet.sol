// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeFacet {
    function sendDeposit(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendWithdraw(uint16 appId, bytes memory appPayload)
        external
        payable;

    function sendDepositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable;
}
