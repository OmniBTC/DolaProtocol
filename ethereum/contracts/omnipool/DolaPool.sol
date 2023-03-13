// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../libraries/LibAsset.sol";
import "../libraries/LibPoolCodec.sol";
import "../libraries/LibDecimals.sol";
import "../libraries/LibDolaTypes.sol";

contract DolaPool {
    // Dola chain id
    uint16 immutable dolaChainId;
    // Save the dola contract address that allowns to manage spender
    address[] allOwners;
    mapping(address => uint256) public owners;
    // Save the dola contract address that allows withdrawals
    address[] allSpenders;
    mapping(address => uint256) public spenders;

    /// Events

    /// Deposit coin
    event DepositPool(address pool, address spender, uint256 amount);

    /// Withdraw coin
    event WithdrawPool(address pool, address receiver, uint256 amount);

    modifier isSpender(address spender) {
        require(spenders[spender] != 0, "NOT REGISTER SPENDER");
        _;
    }

    modifier isOwner(address owner) {
        require(owners[owner] != 0, "NOT REGISTER OWNER");
        _;
    }

    constructor(uint16 _dolaChainId, address _basicBridge) {
        dolaChainId = _dolaChainId;
        allOwners.push(_basicBridge);
        owners[_basicBridge] = allOwners.length;
        allSpenders.push(_basicBridge);
        spenders[_basicBridge] = allSpenders.length;
    }

    /// Call by governance

    /// Register owner by owner
    function registerOwner(address newOwner) public isOwner(msg.sender) {
        require(owners[newOwner] == 0, "HAS REGISTER OWNER");
        allOwners.push(newOwner);
        owners[newOwner] = allOwners.length;
    }

    /// Delete owner by owner
    function deleteOwner(address deletedOwner) public isOwner(msg.sender) {
        require(owners[deletedOwner] != 0, "NOT REGISTER OWNER");
        uint256 index = owners[deletedOwner];
        owners[deletedOwner] = 0;

        if (index != allOwners.length) {
            address needMoved = allOwners[allOwners.length - 1];
            allOwners[index - 1] = needMoved;
            owners[needMoved] = index;
        }
        allOwners.pop();
    }

    /// Register spender by owner
    function registerSpender(address newSpender) public isOwner(msg.sender) {
        require(spenders[newSpender] == 0, "HAS REGISTER SPENDER");
        allSpenders.push(newSpender);
        spenders[newSpender] = allSpenders.length;
    }

    /// Delete spender by owner
    function deleteSpender(address deletedSpender) public isOwner(msg.sender) {
        require(spenders[deletedSpender] != 0, "NOT REGISTER SPENDER");
        uint256 index = spenders[deletedSpender];
        spenders[deletedSpender] = 0;

        if (index != allSpenders.length) {
            address needMoved = allSpenders[allSpenders.length - 1];
            allSpenders[index - 1] = needMoved;
            spenders[needMoved] = index;
        }
        allSpenders.pop();
    }

    /// Call by bridge

    /// Deposit to pool
    function deposit(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) public payable returns (bytes memory) {
        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);

        bytes memory poolPayload = LibPoolCodec.encodeDepositPayload(
            LibDolaTypes.addressToDolaAddress(dolaChainId, token),
            LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
            LibDecimals.fixAmountDecimals(
                amount,
                LibAsset.queryDecimals(token)
            ),
            appId,
            appPayload
        );
        emit DepositPool(tx.origin, token, amount);
        return poolPayload;
    }

    /// Withdraw from the pool. Only bridges that are registered spender are allowed to make calls
    function withdraw(
        LibDolaTypes.DolaAddress memory userAddress,
        uint64 amount,
        LibDolaTypes.DolaAddress memory poolAddress
    ) public isSpender(msg.sender) {
        address pool = LibDolaTypes.dolaAddressToAddress(poolAddress);
        address user = LibDolaTypes.dolaAddressToAddress(userAddress);
        uint256 fixedAmount = LibDecimals.restoreAmountDecimals(
            amount,
            LibAsset.queryDecimals(pool)
        );
        require(userAddress.dolaChainId == dolaChainId, "INVALID DST CHAIN");
        LibAsset.transferAsset(pool, payable(user), fixedAmount);
        emit WithdrawPool(pool, user, fixedAmount);
    }

    /// Send pool message that do not involve incoming or outgoing funds
    function sendMessage(uint16 appId, bytes memory appPayload)
        public
        view
        returns (bytes memory)
    {
        return
            LibPoolCodec.encodeSendMessagePayload(
                LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
                appId,
                appPayload
            );
    }

    receive() external payable {}
}
