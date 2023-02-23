// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeBridge {
    function sendLendingHelperPayload(uint16[] memory dolaPoolIds, uint8 callType) external payable;

    function sendProtocolPayload(
        uint64 nonce,
        uint8 callType,
        uint16 bindDolaChainId,
        bytes memory bindAddress
    ) external payable;

    function sendDeposit(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendWithdraw(
        bytes memory pool,
        uint16 appId,
        bytes memory appPayload
    ) external payable;

    function sendDepositAndWithdraw(
        address depositToken,
        uint256 depositAmount,
        uint16 withdrawChainId,
        bytes memory withdrawToken,
        uint16 appId,
        bytes memory appPayload
    ) external payable;
}
