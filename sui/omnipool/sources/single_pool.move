// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// The Sui single pool module is responsible for hosting Sui user assets. When the single currency pool starts,
/// Wormhole is used as the basic bridge. In the future, more bridges can be introduced through governance without
/// changing the single currency pool module.
module omnipool::single_pool {
    use std::ascii;
    use std::type_name;

    use dola_types::dola_address::{Self, DolaAddress};
    use dola_types::dola_contract::{Self, DolaContract};
    use sui::balance::{Self, Balance, zero};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use omnipool::codec_pool;

    friend omnipool::wormhole_adapter_pool;

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;
    use std::vector;
    use sui::event;

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


    /// The user_address's information is recorded in the protocol, and the pool only needs to record itself
    struct Pool<phantom CoinType> has key, store {
        id: UID,
        balance: Balance<CoinType>,
        decimal: u8
    }

    /// Give permission to the bridge for pool
    struct PoolApproval has key {
        id: UID,
        // Save the dola contract address that allowns to manage spender
        owners: vector<u256>,
        // Save the dola contract address that allows withdrawals
        spenders: vector<u256>
    }

    /// Events

    /// Deposit coin
    struct DepositCoin<phantom CoinType> has copy, drop {
        sender: address,
        amount: u64
    }

    /// Withdraw coin
    struct WithdrawCoin<phantom CoinType> has copy, drop {
        receiver: address,
        amount: u64
    }


    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolApproval {
            id: object::new(ctx),
            owners: vector::empty(),
            spenders: vector::empty()
        });
    }

    /// Register owner and spender for basic bridge
    public(friend) fun register_basic_bridge(
        pool_approval: &mut PoolApproval,
        dola_contract: &DolaContract
    ) {
        let dola_contract = dola_contract::get_dola_contract(dola_contract);
        assert!(!vector::contains(&pool_approval.owners, &dola_contract), EHAS_REGISTER_OWNER);
        assert!(!vector::contains(&pool_approval.spenders, &dola_contract), EHAS_REGISTER_SPENDER);

        vector::push_back(&mut pool_approval.owners, dola_contract);
        vector::push_back(&mut pool_approval.spenders, dola_contract);
    }

    /// Call by governance

    /// Register owner by owner
    public fun register_owner(
        pool_approval: &mut PoolApproval,
        old_owner: &DolaContract,
        new_owner: &DolaContract
    ) {
        let old_dola_contract = dola_contract::get_dola_contract(old_owner);
        let new_dola_contract = dola_contract::get_dola_contract(new_owner);
        assert!(vector::contains(&pool_approval.owners, &old_dola_contract), ENOT_REGISTER_OWNER);
        assert!(!vector::contains(&pool_approval.owners, &new_dola_contract), EHAS_REGISTER_OWNER);

        vector::push_back(&mut pool_approval.owners, dola_contract::get_dola_contract(new_owner));
    }

    /// Delete owner by owner
    public fun delete_owner(
        pool_approval: &mut PoolApproval,
        owner: &DolaContract,
        deleted_dola_contract: u256
    ) {
        assert!(vector::contains(&pool_approval.owners, &dola_contract::get_dola_contract(owner)), ENOT_REGISTER_OWNER);
        let (flag, index) = vector::index_of(&mut pool_approval.owners, &deleted_dola_contract);
        assert!(flag, ENOT_REGISTER_OWNER);
        vector::remove(&mut pool_approval.owners, index);
    }

    /// Register spender by owner
    public fun register_spender(
        pool_approval: &mut PoolApproval,
        owner: &DolaContract,
        spender: &DolaContract
    ) {
        let owner_dola_contract = dola_contract::get_dola_contract(owner);
        let spender_dola_contract = dola_contract::get_dola_contract(spender);
        assert!(vector::contains(&pool_approval.owners, &owner_dola_contract), ENOT_REGISTER_OWNER);
        assert!(!vector::contains(&pool_approval.spenders, &spender_dola_contract), EHAS_REGISTER_SPENDER);

        vector::push_back(&mut pool_approval.spenders, spender_dola_contract);
    }

    /// Delete spender by owner
    public fun delete_spender(
        pool_approval: &mut PoolApproval,
        owner: &DolaContract,
        deleted_dola_contract: u256
    ) {
        assert!(vector::contains(&pool_approval.owners, &dola_contract::get_dola_contract(owner)), ENOT_REGISTER_OWNER);
        let (flag, index) = vector::index_of(&mut pool_approval.spenders, &deleted_dola_contract);
        assert!(flag, ENOT_REGISTER_SPENDER);
        vector::remove(&mut pool_approval.spenders, index);
    }

    /// Create pool by anyone
    /// todo! How to prevent users from setting decimal indiscriminately
    public entry fun create_pool<CoinType>(decimal: u8, ctx: &mut TxContext) {
        transfer::share_object(Pool<CoinType> {
            id: object::new(ctx),
            balance: zero<CoinType>(),
            decimal
        })
    }

    /// Call by bridge

    /// Get coin decimal
    public fun get_coin_decimal<CoinType>(pool: &Pool<CoinType>): u8 {
        pool.decimal
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
    public fun normal_amount<CoinType>(pool: &Pool<CoinType>, amount: u64): u64 {
        let cur_decimal = get_coin_decimal<CoinType>(pool);
        let target_decimal = 8;
        convert_amount(amount, cur_decimal, target_decimal)
    }

    /// Unnormal coin amount in dola protocol
    public fun unnormal_amount<CoinType>(pool: &Pool<CoinType>, amount: u64): u64 {
        let cur_decimal = 8;
        let target_decimal = get_coin_decimal<CoinType>(pool);
        convert_amount(amount, cur_decimal, target_decimal)
    }

    /// Deposit coin from portal to sui
    public fun deposit_to<CoinType>(
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let sender = tx_context::sender(ctx);
        let deposit_amount = coin::value(&deposit_coin);

        let amount = normal_amount(pool, deposit_amount);
        let user_address = dola_address::convert_address_to_dola(sender);
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let pool_payload = codec_pool::encode_send_deposit_payload(
            pool_address,
            user_address,
            amount,
            app_id,
            app_payload
        );
        balance::join(&mut pool.balance, coin::into_balance(deposit_coin));
        event::emit(DepositCoin<CoinType> {
            sender,
            amount: deposit_amount
        });

        pool_payload
    }

    /// Withdraw coin from portal to sui
    public fun withdraw_to(
        pool_chain_id: u16,
        pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let sender = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let withdraw_pool = dola_address::create_dola_address(pool_chain_id, pool_address);
        let pool_payload = codec_pool::encode_send_withdraw_payload(withdraw_pool, sender, app_id, app_payload);
        pool_payload
    }

    /// Deposit and withdraw coin from portal to sui
    public fun deposit_and_withdraw<DepositCoinType>(
        deposit_pool: &mut Pool<DepositCoinType>,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_chain_id: u16,
        withdraw_pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let sender = tx_context::sender(ctx);
        let deposit_amount = coin::value(&deposit_coin);

        let amount = normal_amount(deposit_pool, deposit_amount);
        let depoist_user = dola_address::convert_address_to_dola(sender);
        let deposit_pool_address = dola_address::convert_pool_to_dola<DepositCoinType>();
        let withdraw_pool_address = dola_address::create_dola_address(withdraw_chain_id, withdraw_pool_address);
        let pool_payload = codec_pool::encode_send_deposit_and_withdraw_payload(
            deposit_pool_address,
            depoist_user,
            amount,
            withdraw_pool_address,
            app_id,
            app_payload
        );
        balance::join(&mut deposit_pool.balance, coin::into_balance(deposit_coin));
        event::emit(DepositCoin<DepositCoinType> {
            sender,
            amount: deposit_amount
        });

        pool_payload
    }

    /// Withdraw from current pool and call by bridge
    public fun inner_withdraw<CoinType>(
        pool_approval: &PoolApproval,
        dola_contract: &DolaContract,
        pool: &mut Pool<CoinType>,
        user_address: DolaAddress,
        amount: u64,
        pool_address: DolaAddress,
        ctx: &mut TxContext
    ) {
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
                ascii::into_bytes(type_name::into_string(type_name::get<CoinType>())),
            EINVALID_POOL
        );

        let user_address = dola_address::convert_dola_to_address(user_address);
        amount = unnormal_amount(pool, amount);
        let balance = balance::split(&mut pool.balance, amount);
        let coin = coin::from_balance(balance, ctx);
        event::emit(WithdrawCoin<CoinType> {
            receiver: user_address,
            amount
        });

        transfer::transfer(coin, user_address);
    }

    #[test]
    public fun test_encode_decode() {
        let pool = @0x11;
        let user = @0x22;
        let amount = 100;
        let app_id = 0;
        let app_payload = vector[0u8];
        // test encode and decode send_deposit_payload
        let send_deposit_payload = codec_pool::encode_send_deposit_payload(
            dola_address::convert_address_to_dola(pool),
            dola_address::convert_address_to_dola(user),
            amount,
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_amount, decoded_app_id, decoded_app_payload) = codec_pool::decode_send_deposit_payload(
            send_deposit_payload
        );
        assert!(dola_address::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(dola_address::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode send_withdraw_payload
        let send_withdraw_payload = codec_pool::encode_send_withdraw_payload(
            dola_address::convert_address_to_dola(pool),
            dola_address::convert_address_to_dola(user),
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_app_id, decoded_app_payload) = codec_pool::decode_send_withdraw_payload(
            send_withdraw_payload
        );
        assert!(dola_address::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(dola_address::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode send_deposit_and_withdraw_payload
        let withdraw_pool = @0x33;
        let send_deposit_and_withdraw_payload = codec_pool::encode_send_deposit_and_withdraw_payload(
            dola_address::convert_address_to_dola(pool),
            dola_address::convert_address_to_dola(user),
            amount,
            dola_address::convert_address_to_dola(withdraw_pool),
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_amount, decoded_withdraw_pool, decoded_app_id, decoded_app_payload) = codec_pool::decode_send_deposit_and_withdraw_payload(
            send_deposit_and_withdraw_payload
        );
        assert!(dola_address::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(dola_address::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
        assert!(dola_address::convert_dola_to_address(decoded_withdraw_pool) == withdraw_pool, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode receive_withdraw_payload
        let receive_withdraw_payload = codec_pool::encode_receive_withdraw_payload(
            0,
            0,
            dola_address::convert_address_to_dola(pool),
            dola_address::convert_address_to_dola(user),
            amount
        );
        let (_, _, decoded_pool, decoded_user, decoded_amount) = codec_pool::decode_receive_withdraw_payload(
            receive_withdraw_payload
        );
        assert!(dola_address::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(dola_address::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
    }

    #[test]
    public fun test_deposit_to() {
        let manager = @0xA;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            create_pool<SUI>(9, ctx);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(scenario);
            assert!(balance::value(&pool.balance) == 0, 0);
            let ctx = test_scenario::ctx(scenario);
            let coin = coin::mint_for_testing<SUI>(100, ctx);
            let app_payload = vector::empty<u8>();
            deposit_to<SUI>(&mut pool, coin, 0, app_payload, ctx);
            assert!(balance::value(&pool.balance) == 100, 0);
            test_scenario::return_shared(pool);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_withdraw_to() {
        let manager = @0x0;
        let user_address = @0xC;

        let scenario_val = test_scenario::begin(manager);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            init(ctx);

            create_pool<SUI>(9, ctx);
        };
        test_scenario::next_tx(scenario, manager);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(scenario);
            let pool_info = test_scenario::take_shared<PoolInfo>(scenario);

            let manager_cap = register_cap(&mut pool_info, test_scenario::ctx(scenario));
            let ctx = test_scenario::ctx(scenario);
            let pool_address = dola_address::convert_pool_to_dola<SUI>();

            let balance = balance::create_for_testing<SUI>(100);

            balance::join(&mut pool.balance, balance);

            assert!(balance::value(&pool.balance) == 100, 0);

            inner_withdraw<SUI>(
                &manager_cap,
                &mut pool,
                dola_address::convert_address_to_dola(user_address),
                10,
                pool_address,
                ctx
            );

            assert!(balance::value(&pool.balance) == 0, 0);
            delete_cap(&mut pool_info, manager_cap);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(pool_info);
        };
        test_scenario::end(scenario_val);
    }
}
