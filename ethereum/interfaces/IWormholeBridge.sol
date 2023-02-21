// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeBridge {
    function sendBinding(uint64 nonce, uint8 callType, uint16 bindDolaChainId, bytes memory bindAddress) external;

    function sendUnbinding(uint64 nonce, uint8 callType, uint16 unbindDolaChainId, bytes memory unbindAddress) external;

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
