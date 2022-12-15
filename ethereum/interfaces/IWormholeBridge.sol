// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeBridge {
    function sendDeposit(
        bytes memory tokenName,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendWithdraw(
        bytes memory tokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendDepositAndWithdraw(
        bytes memory depositTokenName,
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable;
}
