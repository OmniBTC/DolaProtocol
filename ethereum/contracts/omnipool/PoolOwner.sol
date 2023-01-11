// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IOmniPool.sol";

contract PoolOwner {
    mapping(address => bool) allowances;

    constructor(address bridgePool) {
        allowances[bridgePool] = true;
    }

    modifier isBridgePool() {
        require(allowances[msg.sender] == true, "Not bridge pool!");
        _;
    }

    function rely(address bridge) external isBridgePool {
        allowances[bridge] = true;
    }

    function deny(address bridge) external isBridgePool {
        allowances[bridge] = false;
    }

    function token(address pool) external view returns (address) {
        return IOmniPool(pool).token();
    }

    function decimal(address pool) external view returns (uint8) {
        return IOmniPool(pool).decimals();
    }

    function depositTo(
        address pool,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable isBridgePool returns (bytes memory) {
        if (IOmniPool(pool).token() == address(0) && msg.value >= amount) {
            return
                IOmniPool(pool).depositTo{value: amount}(
                    amount,
                    appId,
                    appPayload
                );
        } else {
            return IOmniPool(pool).depositTo(amount, appId, appPayload);
        }
    }

    function withdrawTo(
        address pool,
        uint16 appId,
        bytes memory appPayload
    ) external view isBridgePool returns (bytes memory) {
        return IOmniPool(pool).withdrawTo(appId, appPayload);
    }

    function innerWithdraw(
        address pool,
        address to,
        uint64 amount
    ) external isBridgePool {
        IOmniPool(pool).innerWithdraw(to, amount);
    }

    function depositAndWithdraw(
        address depositPool,
        uint256 depositAmount,
        address withdrawPool,
        uint16 appId,
        bytes memory appPayload
    ) public payable isBridgePool returns (bytes memory) {
        if (
            IOmniPool(depositPool).token() == address(0) &&
            msg.value >= depositAmount
        ) {
            return
                IOmniPool(depositPool).depositAndWithdraw{value: depositAmount}(
                    depositAmount,
                    withdrawPool,
                    appId,
                    appPayload
                );
        } else {
            return
                IOmniPool(depositPool).depositAndWithdraw(
                    depositAmount,
                    withdrawPool,
                    appId,
                    appPayload
                );
        }
    }
}
