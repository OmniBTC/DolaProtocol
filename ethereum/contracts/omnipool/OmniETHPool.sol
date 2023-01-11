// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../libraries/LibPool.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";

contract OmniETHPool {
    uint256 public balance;
    address public poolOwner;
    address public poolToken;
    uint16 public dolaChainId;

    modifier isPoolOwner() {
        require(msg.sender == poolOwner, "Not pool owner!");
        _;
    }

    constructor(uint16 _dolaChainId, address _poolOwner) {
        dolaChainId = _dolaChainId;
        poolOwner = _poolOwner;
        poolToken = address(0);
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function token() public view returns (address) {
        return poolToken;
    }

    function depositTo(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable isPoolOwner returns (bytes memory) {
        balance += amount;

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
        isPoolOwner
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

    function innerWithdraw(address to, uint64 amount) external isPoolOwner {
        uint256 fixedAmount = LibDecimals.restoreAmountDecimals(
            amount,
            decimals()
        );
        balance -= fixedAmount;
        (bool success, ) = to.call{value: fixedAmount}("");
        require(success, "WETH: ETH transfer failed");
    }

    function depositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) public isPoolOwner returns (bytes memory) {
        balance += depositAmount;

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

    receive() external payable {}
}
