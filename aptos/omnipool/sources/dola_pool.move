// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// The Sui dola pool module is responsible for hosting Sui user assets. When the dola pool starts,
/// Wormhole is used as the basic bridge. In the future, more bridges can be introduced through governance without
/// changing the dola pool module.
module omnipool::dola_pool {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_std::type_info;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};

    use dola_types::dola_address::{Self, DolaAddress};
    use dola_types::dola_contract::{Self, DolaContract};
    use omnipool::pool_codec;

    friend omnipool::wormhole_adapter_pool;

    const SEED: vector<u8> = b"Dola Pool";

    /// Errors

    /// Invalid pool
    const EINVALID_POOL: u64 = 0;

    /// Has register spender
    const EHAS_REGISTER_SPENDER: u64 = 1;

    /// Not register spender
    const ENOT_REGISTER_SPENDER: u64 = 1;

    /// Has register owner
    const EHAS_REGISTER_OWNER: u64 = 2;

    /// Not register owner
    const ENOT_REGISTER_OWNER: u64 = 3;

    /// Invalid dst chain
    const EINVALID_DST_CHAIN: u64 = 4;

    const EHAS_INIT: u64 = 5;

    const ENOT_INIT: u64 = 6;

    const EINVALID_ADMIN: u64 = 7;

    const EHAS_POOL: u64 = 8;

    /// The user_address's information is recorded in the protocol, and the pool only needs to record itself
    struct Pool<phantom CoinType> has key, store {
        balance: Coin<CoinType>
    }

    /// Give permission to the bridge for pool
    struct PoolApproval has key {
        // Manage resource address permissions
        resource_signer_cap: SignerCapability,
        // Save the dola contract address that allowns to manage spender
        owners: vector<u256>,
        // Save the dola contract address that allows withdrawals
        spenders: vector<u256>,
        // Event handle of deposit pool
        deposit_event_handle: EventHandle<DepositPool>,
        // Event handle of withdraw pool
        withdraw_event_handle: EventHandle<WithdrawPool>,
    }

    /// Events

    /// Deposit coin
    struct DepositPool has store, drop {
        pool: String,
        sender: address,
        amount: u64
    }

    /// Withdraw coin
    struct WithdrawPool has store, drop {
        pool: String,
        receiver: address,
        amount: u64
    }

    /// Make sure the user_address has aptos coin, and help register if they don't.
    fun transfer<X>(coin_x: Coin<X>, to: address) {
        if (!coin::is_account_registered<X>(to) && type_info::type_of<X>() == type_info::type_of<AptosCoin>()) {
            aptos_account::create_account(to);
        };
        coin::deposit(to, coin_x);
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @omnipool
    }

    public fun ensure_init(): bool {
        exists<PoolApproval>(get_resource_address())
    }

    public fun exist_pool<CoinType>(): bool {
        exists<Pool<CoinType>>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@omnipool, SEED)
    }

    fun get_resouce_signer(): signer acquires PoolApproval {
        assert!(ensure_init(), ENOT_INIT);
        let dola_contract_registry = borrow_global<PoolApproval>(get_resource_address());
        account::create_signer_with_capability(&dola_contract_registry.resource_signer_cap)
    }

    public entry fun init(sender: &signer) {
        assert!(ensure_admin(sender), EINVALID_ADMIN);
        assert!(!ensure_init(), EHAS_INIT);
        let (resource_signer, resource_signer_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, PoolApproval {
            resource_signer_cap,
            owners: vector::empty(),
            spenders: vector::empty(),
            deposit_event_handle: account::new_event_handle(&resource_signer),
            withdraw_event_handle: account::new_event_handle(&resource_signer)
        });
    }

    /// Register owner and spender for basic bridge
    public(friend) fun register_basic_bridge(
        dola_contract: &DolaContract
    ) acquires PoolApproval {
        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        let dola_contract = dola_contract::get_dola_contract(dola_contract);
        assert!(!vector::contains(&pool_approval.owners, &dola_contract), EHAS_REGISTER_OWNER);
        assert!(!vector::contains(&pool_approval.spenders, &dola_contract), EHAS_REGISTER_SPENDER);

        vector::push_back(&mut pool_approval.owners, dola_contract);
        vector::push_back(&mut pool_approval.spenders, dola_contract);
    }

    /// Call by governance

    /// Register owner by owner
    public fun register_owner(
        old_owner: &DolaContract,
        new_owner: u256
    ) acquires PoolApproval {
        assert!(ensure_init(), ENOT_INIT);
        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        let old_dola_contract = dola_contract::get_dola_contract(old_owner);
        assert!(vector::contains(&pool_approval.owners, &old_dola_contract), ENOT_REGISTER_OWNER);
        assert!(!vector::contains(&pool_approval.owners, &new_owner), EHAS_REGISTER_OWNER);

        vector::push_back(&mut pool_approval.owners, new_owner);
    }

    /// Delete owner by owner
    public fun delete_owner(
        owner: &DolaContract,
        deleted_dola_contract: u256
    ) acquires PoolApproval {
        assert!(ensure_init(), ENOT_INIT);
        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        assert!(vector::contains(&pool_approval.owners, &dola_contract::get_dola_contract(owner)), ENOT_REGISTER_OWNER);
        let (flag, index) = vector::index_of(&mut pool_approval.owners, &deleted_dola_contract);
        assert!(flag, ENOT_REGISTER_OWNER);
        vector::remove(&mut pool_approval.owners, index);
    }

    /// Register spender by owner
    public fun register_spender(
        owner: &DolaContract,
        spender: u256
    ) acquires PoolApproval {
        assert!(ensure_init(), ENOT_INIT);
        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        let owner_dola_contract = dola_contract::get_dola_contract(owner);
        assert!(vector::contains(&pool_approval.owners, &owner_dola_contract), ENOT_REGISTER_OWNER);
        assert!(!vector::contains(&pool_approval.spenders, &spender), EHAS_REGISTER_SPENDER);

        vector::push_back(&mut pool_approval.spenders, spender);
    }

    /// Delete spender by owner
    public fun delete_spender(
        owner: &DolaContract,
        deleted_dola_contract: u256
    ) acquires PoolApproval {
        assert!(ensure_init(), ENOT_INIT);
        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        assert!(vector::contains(&pool_approval.owners, &dola_contract::get_dola_contract(owner)), ENOT_REGISTER_OWNER);
        let (flag, index) = vector::index_of(&mut pool_approval.spenders, &deleted_dola_contract);
        assert!(flag, ENOT_REGISTER_SPENDER);
        vector::remove(&mut pool_approval.spenders, index);
    }

    /// Create pool by anyone
    public entry fun create_pool<CoinType>() acquires PoolApproval {
        assert!(ensure_init(), EHAS_INIT);
        assert!(!exist_pool<CoinType>(), EHAS_POOL);
        let resource_signer = get_resouce_signer();
        move_to(&resource_signer, Pool<CoinType> {
            balance: coin::zero()
        });
    }

    /// Call by bridge

    /// Get coin decimal
    public fun get_coin_decimal<CoinType>(): u8 {
        coin::decimals<CoinType>()
    }

    /// Convert amount from current decimal to target decimal
    public fun convert_amount(amount: u64, cur_decimal: u8, target_decimal: u8): u64 {
        while (cur_decimal != target_decimal) {
            if (cur_decimal < target_decimal) {
                amount = amount * 10;
                cur_decimal = cur_decimal + 1;
            }else {
                amount = amount / 10;
                cur_decimal = cur_decimal - 1;
            };
        };
        amount
    }

    /// Normal coin amount in dola protocol
    public fun normal_amount<CoinType>(amount: u64): u64 {
        let cur_decimal = get_coin_decimal<CoinType>();
        let target_decimal = 8;
        convert_amount(amount, cur_decimal, target_decimal)
    }

    /// Unnormal coin amount in dola protocol
    public fun unnormal_amount<CoinType>(amount: u64): u64 {
        let cur_decimal = 8;
        let target_decimal = get_coin_decimal<CoinType>();
        convert_amount(amount, cur_decimal, target_decimal)
    }

    /// Deposit to pool
    public fun deposit<CoinType>(
        sender: &signer,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
    ): vector<u8> acquires Pool, PoolApproval {
        let deposit_amount = coin::value(&deposit_coin);
        let sender = signer::address_of(sender);
        let amount = normal_amount<CoinType>(deposit_amount);
        let user_address = dola_address::convert_address_to_dola(sender);
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let pool_payload = pool_codec::encode_deposit_payload(
            pool_address, user_address, amount, app_id, app_payload
        );
        let pool = borrow_global_mut<Pool<CoinType>>(get_resource_address());
        coin::merge(&mut pool.balance, deposit_coin);

        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        event::emit_event(&mut pool_approval.deposit_event_handle, DepositPool {
            pool: type_info::type_name<CoinType>(),
            sender,
            amount: deposit_amount
        });

        pool_payload
    }

    /// Withdraw from the pool. Only bridges that are registered spender are allowed to make calls
    public fun withdraw<CoinType>(
        dola_contract: &DolaContract,
        user_address: DolaAddress,
        amount: u64,
        pool_address: DolaAddress,
    ) acquires PoolApproval, Pool {
        let pool_approval = borrow_global_mut<PoolApproval>(get_resource_address());
        assert!(
            vector::contains(&pool_approval.spenders, &dola_contract::get_dola_contract(dola_contract)),
            ENOT_REGISTER_SPENDER
        );
        assert!(
            dola_address::get_native_dola_chain_id() == dola_address::get_dola_chain_id(&pool_address),
            EINVALID_DST_CHAIN
        );
        assert!(
            dola_address::get_dola_address(&pool_address) ==
                *string::bytes(&type_info::type_name<CoinType>()),
            EINVALID_POOL
        );

        let user_address = dola_address::convert_dola_to_address(user_address);
        amount = unnormal_amount<CoinType>(amount);
        let pool = borrow_global_mut<Pool<CoinType>>(get_resource_address());
        let balance = coin::extract(&mut pool.balance, amount);

        event::emit_event(&mut pool_approval.withdraw_event_handle, WithdrawPool {
            pool: type_info::type_name<CoinType>(),
            receiver: user_address,
            amount
        });

        transfer(balance, user_address);
    }

    /// Send pool message that do not involve incoming or outgoing funds
    public fun send_message(
        sender: &signer,
        app_id: u16,
        app_payload: vector<u8>,
    ): vector<u8> {
        let sender = dola_address::convert_address_to_dola(signer::address_of(sender));
        let pool_payload = pool_codec::encode_send_message_payload(sender, app_id, app_payload);
        pool_payload
    }
}
