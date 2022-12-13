// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../libraries/LibPool.sol";
import "../../libraries/LibDecimals.sol";

contract OmniPool {
    uint256 public balance;
    address public dolaDiamond;
    address public token;
    // todo: use the token name defined by the omnicore
    bytes public tokenName;
    mapping(address => bool) private allowances;

    modifier isBridgePool(address diamond) {
        require(allowances[diamond], "Not bridge pool!");
        _;
    }

    constructor(address diamond, address tokenAddress) {
        dolaDiamond = diamond;
        token = tokenAddress;
        tokenName = bytes(IERC20(token).name());
        allowances[dolaDiamond] = true;
    }

    function decimals() public view returns (uint8) {
        return IERC20(token).decimals();
    }

    function rely(address diamond) external isBridgePool(msg.sender) {
        allowances[diamond] = true;
    }

    function deny(address diamond) external isBridgePool(msg.sender) {
        allowances[diamond] = false;
    }

    function depositTo(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external returns (bytes memory) {
        IERC20(token).transfer(address(this), amount);

        bytes memory poolPayload = LibPool.encodeSendDepositPayload(
            address(this),
            tx.origin,
            LibDecimals.fixAmountDecimals(amount, decimals()),
            tokenName,
            appId,
            appPayload
        );
        return poolPayload;
    }

    function withdrawTo(uint16 appId, bytes memory appPayload)
        external
        view
        returns (bytes memory)
    {
        bytes memory poolPayload = LibPool.encodeSendWithdrawPayload(
            address(this),
            tx.origin,
            tokenName,
            appId,
            appPayload
        );
        return poolPayload;
    }

    function innerWithdraw(address to, uint64 amount)
        external
        isBridgePool(msg.sender)
    {
        IERC20(token).transferFrom(
            address(this),
            to,
            LibDecimals.restoreAmountDecimals(amount, decimals())
        );
    }

    function depositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) public returns (bytes memory) {
        IERC20(token).transfer(address(this), depositAmount);

        bytes memory poolPayload = LibPool.encodeSendDepositAndWithdrawPayload(
            address(this),
            tx.origin,
            LibDecimals.fixAmountDecimals(depositAmount, decimals()),
            tokenName,
            withdrawPool,
            withdrawUser,
            withdrawTokenName,
            appId,
            appPayload
        );

        return poolPayload;
    }
}
