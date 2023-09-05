// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibGovCodec.sol";
import "./LibPoolCodec.sol";

library LibBoolAdapterVerify {
    uint8 internal constant REMAPPING_ADD_RELAYER_OPCODE = 1;
    uint8 internal constant REMAPPING_REMOVE_RELAYER_OPCODE = 2;
    uint8 internal constant REMAPPING_POOL_REGISTER_SPENDER = 3;
    uint8 internal constant REMAPPING_POOL_DELETE_SPENDER = 4;
    uint8 internal constant REMAPPING_POOL_WITHDRAW = 5;

    function replayProtect(
        mapping(bytes32 => bool) storage consumedMsgs,
        bytes32 txUniqueIdentification,
        bytes memory payload
    ) internal {
        bytes32 hash = keccak256(abi.encode(txUniqueIdentification,payload));

        require(!consumedMsgs[hash], "ALREADY COMPLETED");

        consumedMsgs[hash] = true;
    }
}