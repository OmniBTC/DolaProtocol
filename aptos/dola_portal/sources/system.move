// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_portal::system {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event::{Self, EventHandle};

    use dola_portal::system_codec;
    use dola_types::dola_address;
    use omnipool::wormhole_adapter_pool;
    use wormhole::state;

    const SEED: vector<u8> = b"Dola System Portal";

    /// App id
    const SYSTEM_APP_ID: u16 = 0;

    /// Errors

    const EHAS_INIT: u64 = 5;

    const ENOT_INIT: u64 = 6;

    const EINVALID_ADMIN: u64 = 7;

    const EHAS_POOL: u64 = 8;

    struct SystemPortal has key {
        resource_signer_cap: SignerCapability,
        system_event_handle: EventHandle<SystemPortalEvent>,
        relay_event_handle: EventHandle<RelayEvent>
    }

    /// Events

    struct RelayEvent has drop, store {
        nonce: u64,
        amount: u64
    }

    struct SystemPortalEvent has drop, store {
        nonce: u64,
        sender: address,
        source_chain_id: u16,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @dola_portal
    }

    public fun ensure_init(): bool {
        exists<SystemPortal>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@dola_portal, SEED)
    }

    fun get_resouce_signer(): signer acquires SystemPortal {
        assert!(ensure_init(), ENOT_INIT);
        let dola_contract_registry = borrow_global<SystemPortal>(get_resource_address());
        account::create_signer_with_capability(&dola_contract_registry.resource_signer_cap)
    }

    public entry fun init(sender: &signer) {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        assert!(!ensure_init(), EHAS_INIT);
        let (resource_signer, resource_signer_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, SystemPortal {
            resource_signer_cap,
            system_event_handle: account::new_event_handle(&resource_signer),
            relay_event_handle: account::new_event_handle(&resource_signer)
        });
    }

    public entry fun binding(
        sender: &signer,
        dola_chain_id: u16,
        binded_address: vector<u8>,
        relay_fee: u64
    ) acquires SystemPortal {
        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let bind_address = dola_address::create_dola_address(dola_chain_id, binded_address);
        let app_payload = system_codec::encode_bind_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            bind_address,
            system_codec::get_binding_type()
        );
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            SYSTEM_APP_ID,
            app_payload
        );
        let event_handle = borrow_global_mut<SystemPortal>(get_resource_address());

        let fee = coin::withdraw<AptosCoin>(sender, relay_fee);
        coin::deposit<AptosCoin>(@dola_portal, fee);

        event::emit_event(
            &mut event_handle.relay_event_handle,
            RelayEvent {
                nonce: sequence,
                amount: relay_fee
            }
        );

        event::emit_event(
            &mut event_handle.system_event_handle,
            SystemPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                user_chain_id: dola_chain_id,
                user_address: binded_address,
                call_type: system_codec::get_binding_type()
            }
        )
    }

    public entry fun unbinding(
        sender: &signer,
        dola_chain_id: u16,
        unbinded_address: vector<u8>,
        relay_fee: u64
    ) acquires SystemPortal {
        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let bind_address = dola_address::create_dola_address(dola_chain_id, unbinded_address);
        let app_payload = system_codec::encode_bind_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            bind_address,
            system_codec::get_unbinding_type()
        );
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            SYSTEM_APP_ID,
            app_payload
        );
        let event_handle = borrow_global_mut<SystemPortal>(get_resource_address());

        let fee = coin::withdraw<AptosCoin>(sender, relay_fee);
        coin::deposit<AptosCoin>(@dola_portal, fee);

        event::emit_event(
            &mut event_handle.relay_event_handle,
            RelayEvent {
                nonce: sequence,
                amount: relay_fee
            }
        );

        event::emit_event(
            &mut event_handle.system_event_handle,
            SystemPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                user_chain_id: dola_chain_id,
                user_address: unbinded_address,
                call_type: system_codec::get_unbinding_type()
            }
        )
    }
}
