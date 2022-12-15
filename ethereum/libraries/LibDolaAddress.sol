// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library LibDolaAddress {
    struct DolaAddress {
        uint16 dolaChainId;
        bytes externalAddress;
    }
}
