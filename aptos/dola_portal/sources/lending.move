// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_portal::lending {
    use std::bcs;
    use std::signer;
    use std::vector;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event::{Self, EventHandle};

    use dola_portal::lending_codec;
    use dola_types::dola_address;
    use omnipool::dola_pool;
    use omnipool::wormhole_adapter_pool;
    use wormhole::state;

    const SEED: vector<u8> = b"Dola Lending Portal";

    /// App id
    const LENDING_APP_ID: u16 = 1;

    /// Errors

    const EHAS_INIT: u64 = 5;

    const ENOT_INIT: u64 = 6;

    const EINVALID_ADMIN: u64 = 7;

    const EHAS_POOL: u64 = 8;

    struct LendingPortal has key {
        resource_signer_cap: SignerCapability,
        lending_event_handle: EventHandle<LendingPortalEvent>,
        relay_event_handle: EventHandle<RelayEvent>
    }

    /// Events

    struct RelayEvent has drop, store {
        nonce: u64,
        amount: u64
    }

    struct LendingPortalEvent has drop, store {
        nonce: u64,
        sender: address,
        dola_pool_address: vector<u8>,
        source_chain_id: u16,
        dst_chain_id: u16,
        receiver: vector<u8>,
        amount: u64,
        call_type: u8
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @dola_portal
    }

    public fun ensure_init(): bool {
        exists<LendingPortal>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@dola_portal, SEED)
    }

    fun get_resouce_signer(): signer acquires LendingPortal {
        assert!(ensure_init(), ENOT_INIT);
        let dola_contract_registry = borrow_global<LendingPortal>(get_resource_address());
        account::create_signer_with_capability(&dola_contract_registry.resource_signer_cap)
    }

    public entry fun init(sender: &signer) {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        assert!(!ensure_init(), EHAS_INIT);
        let (resource_signer, resource_signer_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, LendingPortal {
            resource_signer_cap,
            lending_event_handle: account::new_event_handle(&resource_signer),
            relay_event_handle: account::new_event_handle(&resource_signer)
        });
    }

    public entry fun supply<CoinType>(
        sender: &signer,
        deposit_coin: u64,
        relay_fee: u64
    ) acquires LendingPortal {
        let user = dola_address::convert_address_to_dola(signer::address_of(sender));
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let amount = dola_pool::normal_amount<CoinType>(deposit_coin);
        let app_payload = lending_codec::encode_deposit_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            user,
            lending_codec::get_supply_type()
        );
        let deposit_coin = coin::withdraw<CoinType>(sender, deposit_coin);

        let sequence = wormhole_adapter_pool::send_deposit(
            sender,
            wormhole_message_fee,
            deposit_coin,
            LENDING_APP_ID,
            app_payload
        );
        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address::get_dola_address(&dola_address::convert_pool_to_dola<CoinType>()),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: 0,
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount,
                call_type: lending_codec::get_supply_type()
            }
        )
    }

    public entry fun withdraw_local<CoinType>(
        sender: &signer,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        relay_fee: u64
    ) acquires LendingPortal {
        let receiver = dola_address::create_dola_address(dst_chain, receiver_addr);

        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let amount = dola_pool::normal_amount<CoinType>(amount);
        let withdraw_pool = dola_address::convert_pool_to_dola<CoinType>();
        let app_payload = lending_codec::encode_withdraw_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            amount,
            withdraw_pool,
            receiver,
            lending_codec::get_withdraw_type()
        );
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address::get_dola_address(&dola_address::convert_pool_to_dola<CoinType>()),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dst_chain,
                receiver: receiver_addr,
                amount,
                call_type: lending_codec::get_withdraw_type()
            }
        )
    }

    public entry fun withdraw_remote(
        sender: &signer,
        receiver_addr: vector<u8>,
        pool: vector<u8>,
        dst_chain: u16,
        amount: u64,
        relay_fee: u64,
    ) acquires LendingPortal {
        let receiver = dola_address::create_dola_address(dst_chain, receiver_addr);
        let withdraw_pool = dola_address::create_dola_address(dst_chain, pool);

        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let app_payload = lending_codec::encode_withdraw_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            amount,
            withdraw_pool,
            receiver,
            lending_codec::get_withdraw_type()
        );

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: pool,
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dst_chain,
                receiver: receiver_addr,
                amount,
                call_type: lending_codec::get_withdraw_type()
            }
        )
    }

    public entry fun borrow_local<CoinType>(
        sender: &signer,
        receiver_addr: vector<u8>,
        dst_chain: u16,
        amount: u64,
        relay_fee: u64,
    ) acquires LendingPortal {
        let receiver = dola_address::create_dola_address(dst_chain, receiver_addr);

        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let amount = dola_pool::normal_amount<CoinType>(amount);
        let withdraw_pool = dola_address::convert_pool_to_dola<CoinType>();
        let app_payload = lending_codec::encode_withdraw_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            amount,
            withdraw_pool,
            receiver,
            lending_codec::get_borrow_type()
        );
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address::get_dola_address(&dola_address::convert_pool_to_dola<CoinType>()),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dst_chain,
                receiver: receiver_addr,
                amount,
                call_type: lending_codec::get_borrow_type()
            }
        )
    }

    public entry fun borrow_remote(
        sender: &signer,
        receiver_addr: vector<u8>,
        pool: vector<u8>,
        dst_chain: u16,
        amount: u64,
        relay_fee: u64,
    ) acquires LendingPortal {
        let receiver = dola_address::create_dola_address(dst_chain, receiver_addr);
        let borrow_pool = dola_address::create_dola_address(dst_chain, pool);

        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let app_payload = lending_codec::encode_withdraw_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            amount,
            borrow_pool,
            receiver,
            lending_codec::get_borrow_type()
        );
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());
        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: pool,
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dst_chain,
                receiver: receiver_addr,
                amount,
                call_type: lending_codec::get_borrow_type()
            }
        )
    }

    public entry fun repay<CoinType>(
        sender: &signer,
        repay_coin: u64,
        relay_fee: u64,
    ) acquires LendingPortal {
        let user_address = dola_address::convert_address_to_dola(signer::address_of(sender));

        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let amount = dola_pool::normal_amount<CoinType>(repay_coin);
        let app_payload = lending_codec::encode_deposit_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            user_address,
            lending_codec::get_repay_type()
        );
        let repay_coin = coin::withdraw<CoinType>(sender, repay_coin);

        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_deposit(
            sender,
            wormhole_message_fee,
            repay_coin,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address::get_dola_address(&dola_address::convert_pool_to_dola<CoinType>()),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: 0,
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount,
                call_type: lending_codec::get_repay_type()
            }
        )
    }

    public entry fun liquidate<DebtCoinType>(
        sender: &signer,
        debt_amount: u64,
        liquidate_chain_id: u16,
        liquidate_pool_address: vector<u8>,
        // punished person
        liquidate_user_id: u64,
        relay_fee: u64,
    ) acquires LendingPortal {
        let withdraw_pool = dola_address::create_dola_address(liquidate_chain_id, liquidate_pool_address);

        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let app_payload = lending_codec::encode_liquidate_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            withdraw_pool,
            liquidate_user_id
        );

        let debt_coin = coin::withdraw<DebtCoinType>(sender, debt_amount);
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_deposit<DebtCoinType>(
            sender,
            wormhole_message_fee,
            debt_coin,
            LENDING_APP_ID,
            app_payload,
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: dola_address::get_dola_address(&dola_address::convert_pool_to_dola<DebtCoinType>()),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: 0,
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount: debt_amount,
                call_type: lending_codec::get_liquidate_type()
            }
        )
    }

    public entry fun as_collateral(
        sender: &signer,
        dola_pool_ids: vector<u16>,
        relay_fee: u64,
    ) acquires LendingPortal {
        let app_payload = lending_codec::encode_manage_collateral_payload(
            dola_pool_ids,
            lending_codec::get_as_colleteral_type()
        );
        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: vector::empty(),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: 0,
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount: 0,
                call_type: lending_codec::get_as_colleteral_type()
            }
        )
    }

    public entry fun cancel_as_collateral(
        sender: &signer,
        dola_pool_ids: vector<u16>,
        relay_fee: u64,
    ) acquires LendingPortal {
        let app_payload = lending_codec::encode_manage_collateral_payload(
            dola_pool_ids,
            lending_codec::get_cancel_as_colleteral_type()
        );
        let nonce = wormhole_adapter_pool::next_vaa_nonce();
        let wormhole_message_fee = coin::withdraw<AptosCoin>(sender, state::get_message_fee());

        let sequence = wormhole_adapter_pool::send_message(
            sender,
            wormhole_message_fee,
            LENDING_APP_ID,
            app_payload
        );

        let event_handle = borrow_global_mut<LendingPortal>(get_resource_address());

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
            &mut event_handle.lending_event_handle,
            LendingPortalEvent {
                nonce,
                sender: signer::address_of(sender),
                dola_pool_address: vector::empty(),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: 0,
                receiver: bcs::to_bytes(&signer::address_of(sender)),
                amount: 0,
                call_type: lending_codec::get_cancel_as_colleteral_type()
            }
        )
    }
}
