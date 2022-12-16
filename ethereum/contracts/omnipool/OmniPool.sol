// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../libraries/LibPool.sol";
import "../../libraries/LibDecimals.sol";
import "../../libraries/LibDolaTypes.sol";

contract OmniPool {
    uint256 public balance;
    address public bridegPool;
    address public token;
    uint16 public dolaPoolId;
    uint16 public dolaChainId;
    mapping(address => bool) private allowances;

    modifier isBridgePool(address bridge) {
        require(allowances[bridge], "Not bridge pool!");
        _;
    }

    constructor(
        uint16 poolId,
        uint16 chainId,
        address bridge,
        address tokenAddress
    ) {
        bridegPool = bridge;
        token = tokenAddress;
        dolaPoolId = poolId;
        dolaChainId = chainId;
        allowances[bridegPool] = true;
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
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        bytes memory poolPayload = LibPool.encodeSendDepositPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, address(this)),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDecimals.fixAmountDecimals(amount, decimals()),
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
            LibDolaTypes.addressToDolaAddress(dolaChainId, address(this)),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
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
        uint16 appId,
        bytes memory appPayload
    ) public returns (bytes memory) {
        IERC20(token).transferFrom(msg.sender, address(this), depositAmount);

        bytes memory poolPayload = LibPool.encodeSendDepositAndWithdrawPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, address(this)),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDecimals.fixAmountDecimals(depositAmount, decimals()),
            LibDolaTypes.addressToDolaAddress(dolaChainId, withdrawPool),
            appId,
            appPayload
        );

        return poolPayload;
    }
}
