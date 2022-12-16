// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeBridge {
    function sendDeposit(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendWithdraw(
        address pool,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendDepositAndWithdraw(
        address depositPool,
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) external payable;
}
