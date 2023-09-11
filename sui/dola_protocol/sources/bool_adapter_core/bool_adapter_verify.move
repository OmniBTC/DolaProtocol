// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Verification logic module for boolnet message. Including:
/// 1) verifying the signature
/// 2) ensuring that the VAA has not been reused
/// 3) verifying the reliability of the source of the message
module dola_protocol::bool_adapter_verify {
    use std::vector;

    use boolamt::consumer;
    use boolamt::anchor::{GlobalState, AnchorCap};

    const EINVALID_SERVER_OPCODE: u64 = 1;

    // copy from LibBoolAdapterVerify.sol
    // uint8 internal constant OFFSET = 64;
    // uint8 internal constant SERVER_OPCODE_SYSTEM_BINDING = 0;
    // uint8 internal constant SERVER_OPCODE_SYSTEM_UNBINDING = 1;
    //
    // uint8 internal constant SERVER_OPCODE_LENDING_SUPPLY = 2;
    // uint8 internal constant SERVER_OPCODE_LENDING_WITHDRAW = 3;
    // uint8 internal constant SERVER_OPCODE_LENDING_BORROW = 4;
    // uint8 internal constant SERVER_OPCODE_LENDING_REPAY = 5;
    // uint8 internal constant SERVER_OPCODE_LENDING_LIQUIDATE= 6;
    // uint8 internal constant SERVER_OPCODE_LENDING_COLLATERAL= 7;
    // uint8 internal constant SERVER_OPCODE_LENDING_CANCEL_COLLATERAL= 8;
    //
    // uint8 internal constant CLIENT_OPCODE_ADD_RELAYER = OFFSET + 0; // 64
    // uint8 internal constant CLIENT_OPCODE_REMOVE_RELAYER = OFFSET + 1; // 65
    // uint8 internal constant CLIENT_OPCODE_REGISTER_SPENDER = OFFSET + 2; // 66
    // uint8 internal constant CLIENT_OPCODE_DELETE_SPENDER = OFFSET + 3; // 67
    // uint8 internal constant CLIENT_OPCODE_WITHDRAW = OFFSET + 4; // 68

    const OFFSET: u8 = 64;

    public fun client_opcode_add_relayer(): u8 { return OFFSET + 0 }

    public fun client_opcode_remove_relayer(): u8 { return OFFSET + 1 }

    public fun client_opcode_register_spender(): u8 { return OFFSET + 2 }

    public fun client_opcode_delete_spender(): u8 { return OFFSET + 3 }

    public fun client_opcode_withdraw(): u8 { return OFFSET + 4 }

    public fun server_opcode_system_binding(): u8 { return 0 }

    public fun server_opcode_system_unbinding(): u8 { return 1 }

    public fun server_opcode_lending_supply(): u8 { return 2 }

    public fun server_opcode_lending_withdraw(): u8 { return 3 }

    public fun server_opcode_lending_borrow(): u8 { return 4 }

    public fun server_opcode_lending_repay(): u8 { return 5 }

    public fun server_opcode_lending_liquidate(): u8 { return 6 }

    public fun server_opcode_lending_collateral(): u8 { return 7 }

    public fun server_opcode_lending_cancle_collateral(): u8 { return 8 }

    public fun remapping_opcode(
        payload: &mut vector<u8>,
        opcode: u8
    ) {
        vector::push_back(payload, opcode)
    }

    public fun check_server_opcode(
        msg: &vector<u8>,
        opcode: u8
    ) {
        let payload_len = vector::length(msg);
        let last = vector::borrow(msg, (payload_len - 1));

        assert!(
            opcode == *last,
            EINVALID_SERVER_OPCODE
        )
    }

    public fun is_valid_server_opcode(
        opcode: u8
    ): bool {
        if (opcode < server_opcode_system_binding()
            || opcode > server_opcode_lending_cancle_collateral()) {
            return false
        };

        return true
    }

    /// Parse and verify
    public fun parse_verify_and_replay_protect(
        message_raw: vector<u8>,
        signature: vector<u8>,
        anchor_cap: &AnchorCap,
        bool_state: &mut GlobalState,
    ): vector<u8> {

        // All check here.
        // 1) Verifies message and signatures
        // 2) Deduplicates incoming messages
        let (payload, _) = consumer::receive_message(
            message_raw,
            signature,
            anchor_cap,
            bool_state
        );

        // 3) Check server opcode
        let opcode: u8 = vector::pop_back(&mut payload);
        assert!(is_valid_server_opcode(opcode), EINVALID_SERVER_OPCODE);

        return payload
    }
}
