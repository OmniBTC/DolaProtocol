// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library LibDecimals {
    function fixAmountDecimals(uint256 amount, uint8 decimals)
        internal
        pure
        returns (uint64)
    {
        uint64 fixedAmount;
        if (decimals > 8) {
            fixedAmount = uint64(amount / (10**(decimals - 8)));
        } else if (decimals < 8) {
            fixedAmount = uint64(amount * (10**(8 - decimals)));
        } else {
            fixedAmount = uint64(amount);
        }
        require(fixedAmount > 0, "Fixed amount too low");
        return fixedAmount;
    }

    function restoreAmountDecimals(uint64 amount, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        uint256 restoreAmount;
        if (decimals > 8) {
            restoreAmount = uint256(amount * (10**(decimals - 8)));
        } else if (decimals < 8) {
            restoreAmount = uint256(amount / (10**(8 - decimals)));
        } else {
            restoreAmount = uint256(amount);
        }
        return restoreAmount;
    }
}
