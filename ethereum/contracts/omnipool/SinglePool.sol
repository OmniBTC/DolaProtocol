// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../libraries//LibPool.sol";
import "../libraries//LibDecimals.sol";
import "../libraries//LibDolaTypes.sol";

contract SinglePool {
    uint16 public dolaChainId;
    mapping(address => bool) public allowances;
    mapping(address => uint256) public pools;

    modifier isBridgePool(address bridge) {
        require(allowances[bridge], "Not bridge pool!");
        _;
    }

    constructor(uint16 _dolaChainId, address bridge) {
        dolaChainId = _dolaChainId;
        allowances[bridge] = true;
    }

    function decimals(address token) public view returns (uint8) {
        if (token == address(0)) {
            return 18;
        } else {
            return IERC20(token).decimals();
        }
    }

    function rely(address bridge) external isBridgePool(msg.sender) {
        allowances[bridge] = true;
    }

    function deny(address bridge) external isBridgePool(msg.sender) {
        allowances[bridge] = false;
    }

    function depositTo(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable isBridgePool(msg.sender) returns (bytes memory) {
        if (token != address(0)) {
            bool success = IERC20(token).transferFrom(
                tx.origin,
                address(this),
                amount
            );
            require(success, "transfer from failed!");
        }
        pools[token] += amount;

        bytes memory poolPayload = LibPool.encodeSendDepositPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, token),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDecimals.fixAmountDecimals(amount, decimals(token)),
            appId,
            appPayload
        );
        return poolPayload;
    }

    function withdrawTo(
        bytes memory token,
        uint16 appId,
        bytes memory appPayload
    ) external view isBridgePool(msg.sender) returns (bytes memory) {
        bytes memory poolPayload = LibPool.encodeSendWithdrawPayload(
            LibDolaTypes.DolaAddress(dolaChainId, token),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            appId,
            appPayload
        );
        return poolPayload;
    }

    function innerWithdraw(
        address token,
        address to,
        uint64 amount
    ) external isBridgePool(msg.sender) {
        uint256 fixedAmount = LibDecimals.restoreAmountDecimals(
            amount,
            decimals(token)
        );
        if (token == address(0)) {
            (bool success, ) = to.call{value: fixedAmount}("");
            require(success, "ETH transfer failed");
        } else {
            bool success = IERC20(token).transfer(to, fixedAmount);
            require(success, "transfer to failed!");
        }
        pools[token] -= fixedAmount;
    }

    function depositAndWithdraw(
        address depositToken,
        uint256 depositAmount,
        uint16 withdrawChainId,
        bytes memory withdrawToken,
        uint16 appId,
        bytes memory appPayload
    ) public payable isBridgePool(msg.sender) returns (bytes memory) {
        if (depositToken != address(0)) {
            bool success = IERC20(depositToken).transferFrom(
                tx.origin,
                address(this),
                depositAmount
            );
            require(success, "transfer from failed!");
        }
        pools[depositToken] = depositAmount;

        bytes memory poolPayload = LibPool.encodeSendDepositAndWithdrawPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, depositToken),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDecimals.fixAmountDecimals(
                depositAmount,
                decimals(depositToken)
            ),
            LibDolaTypes.DolaAddress(withdrawChainId, withdrawToken),
            appId,
            appPayload
        );

        return poolPayload;
    }

    receive() external payable {}
}
