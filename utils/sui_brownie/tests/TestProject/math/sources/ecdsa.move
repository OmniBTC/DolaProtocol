// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

// A basic ECDSA utility contract to do the following:
// 1) Hash a piece of data using keccak256, output an object with hashed data.
// 2) Recover a Secp256k1 signature to its public key, output an object with the public key.
// 3) Verify a Secp256k1 signature, produce an event for whether it is verified.
module math::ecdsa_k1 {
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::hash;

    /// Event on whether the signature is verified
    struct VerifiedEvent has copy, drop {
        is_verified: bool,
    }

    /// Object that holds the output data
    struct Output has key, store {
        id: UID,
        value: vector<u8>
    }

    public entry fun keccak256(data: vector<u8>, recipient: address, ctx: &mut TxContext) {
        let hashed = Output {
            id: object::new(ctx),
            value: hash::keccak256(&data),
        };
        // Transfer an output data object holding the hashed data to the recipient.
        transfer::public_transfer(hashed, recipient)
    }
}
