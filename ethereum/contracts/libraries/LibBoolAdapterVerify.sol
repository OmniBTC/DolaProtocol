// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./LibBytes.sol";
import "./LibGovCodec.sol";
import "./LibPoolCodec.sol";

library LibBoolAdapterVerify {
    uint8 internal constant OFFSET = 64;

    uint8 internal constant SERVER_OPCODE_SYSTEM_BINDING = 0;
    uint8 internal constant SERVER_OPCODE_SYSTEM_UNBINDING = 1;

    uint8 internal constant SERVER_OPCODE_LENDING_SUPPLY = 2;
    uint8 internal constant SERVER_OPCODE_LENDING_WITHDRAW = 3;
    uint8 internal constant SERVER_OPCODE_LENDING_BORROW = 4;
    uint8 internal constant SERVER_OPCODE_LENDING_REPAY = 5;
    uint8 internal constant SERVER_OPCODE_LENDING_LIQUIDATE= 6;
    uint8 internal constant SERVER_OPCODE_LENDING_COLLATERAL= 7;
    uint8 internal constant SERVER_OPCODE_LENDING_CANCEL_COLLATERAL= 8;

    uint8 internal constant CLIENT_OPCODE_ADD_RELAYER = OFFSET + 0; // 64
    uint8 internal constant CLIENT_OPCODE_REMOVE_RELAYER = OFFSET + 1; // 65
    uint8 internal constant CLIENT_OPCODE_REGISTER_SPENDER = OFFSET + 2; // 66
    uint8 internal constant CLIENT_OPCODE_DELETE_SPENDER = OFFSET + 3; // 67
    uint8 internal constant CLIENT_OPCODE_WITHDRAW = OFFSET + 4; // 68


    function replayProtect(
        mapping(bytes32 => bool) storage consumedMsgs,
        bytes32 txUniqueIdentification,
        bytes memory payload
    ) internal {
        bytes32 hash = keccak256(abi.encode(txUniqueIdentification,payload));

        require(!consumedMsgs[hash], "ALREADY COMPLETED");

        consumedMsgs[hash] = true;
    }

    function remapping_opcode(
        bytes memory payload,
        uint8 opcode
    ) public returns (bytes memory) {
        bytes memory new_payload = new bytes(payload.length + 1);

        for (uint i = 0; i < payload.length; i++) {
            new_payload[i] = payload[i];
        }

        new_payload[payload.length] = bytes1(opcode);

        return new_payload;
    }
}