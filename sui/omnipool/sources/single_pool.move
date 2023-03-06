// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: Apache-2.0

/// The Sui single pool module is responsible for hosting Sui user assets. When the single currency pool starts,
/// Wormhole is used as the basic bridge. In the future, more bridges can be introduced through governance without
/// changing the single currency pool module.
module omnipool::single_pool {
    use std::ascii;
    use std::type_name;

    use dola_types::types::{Self, DolaAddress};
    use dola_types::dola_contract::{Self, DolaContract};
    use sui::balance::{Self, Balance, zero};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer::{Self, share_object};
    use sui::tx_context::{Self, TxContext};

    use omnipool::codec_pool;

    friend omnipool::wormhole_adapter_pool;

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;
    use std::vector;

    const EINVALID_LENGTH: u64 = 0;

    const EMUST_DEPLOYER: u64 = 1;

    const EINVALID_TOKEN: u64 = 2;

    const EINVALID_WITHDRAW: u64 = 2;

    const EINVALID_OWNER: u64 = 2;

    const EINVALID_CHAIN: u64 = 3;


    /// The user_addr's information is recorded in the protocol, and the pool only needs to record itself
    struct Pool<phantom CoinType> has key, store {
        id: UID,
        balance: Balance<CoinType>,
        decimal: u8
    }

    /// Give permission to the bridge for pool
    struct PoolApproval has key {
        id: UID,
        // Save the dola_contract address for administrative privileges
        owners: vector<u256>,
        // Save the address of the dola_contract that allows withdrawals
        spenders: vector<u256>
    }


    fun init(ctx: &mut TxContext) {
        transfer::share_object(PoolApproval {
            id: object::new(ctx),
            owners: vector::empty(),
            spenders: vector::empty()
        });
    }


    public(friend) fun register_basic_bridge(
        pool_approval: &mut PoolApproval,
        dola_contract: &DolaContract
    ) {
        vector::push_back(&mut pool_approval.owners, dola_contract::get_dola_contract(dola_contract));
        vector::push_back(&mut pool_approval.spenders, dola_contract::get_dola_contract(dola_contract));
    }

    public fun register_new_owner(
        pool_approval: &mut PoolApproval,
        old_owner_emitter: &DolaContract,
        new_owner_emitter: &DolaContract
    ){
        assert!(vector::contains(&pool_approval.owners, &dola_contract::get_dola_contract(old_owner_emitter)), EINVALID_OWNER);
        vector::push_back(&mut pool_approval.owners, dola_contract::get_dola_contract(new_owner_emitter));
    }

    public fun register_new_spender(
        pool_approval: &mut PoolApproval,
        owner_emitter: &DolaContract,
        spend_emitter: &DolaContract
    ){
        assert!(vector::contains(&pool_approval.owners, &dola_contract::get_dola_contract(owner_emitter)), EINVALID_OWNER);
        vector::push_back(&mut pool_approval.spenders, dola_contract::get_dola_contract(spend_emitter));
    }

    /// todo! Realize cross create pool
    public entry fun create_pool<CoinType>(decimal: u8, ctx: &mut TxContext) {
        share_object(Pool<CoinType> {
            id: object::new(ctx),
            balance: zero<CoinType>(),
            decimal
        })
    }

    public fun get_coin_decimal<CoinType>(pool: &Pool<CoinType>): u8 {
        pool.decimal
    }

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

    /// Normal amount in dola protocol
    /// 1. Pool class normal
    /// 2. Application class normal
    public fun normal_amount<CoinType>(pool: &Pool<CoinType>, amount: u64): u64 {
        let cur_decimal = get_coin_decimal<CoinType>(pool);
        let target_decimal = 8;
        convert_amount(amount, cur_decimal, target_decimal)
    }

    public fun unnormal_amount<CoinType>(pool: &Pool<CoinType>, amount: u64): u64 {
        let cur_decimal = 8;
        let target_decimal = get_coin_decimal<CoinType>(pool);
        convert_amount(amount, cur_decimal, target_decimal)
    }

    /// call by user_addr or application
    public fun deposit_to<CoinType>(
        pool: &mut Pool<CoinType>,
        deposit_coin: Coin<CoinType>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let amount = normal_amount(pool, coin::value(&deposit_coin));
        let user_addr = types::convert_address_to_dola(tx_context::sender(ctx));
        let pool_addr = types::convert_pool_to_dola<CoinType>();
        let pool_payload = codec_pool::encode_send_deposit_payload(pool_addr, user_addr, amount, app_id, app_payload);
        balance::join(&mut pool.balance, coin::into_balance(deposit_coin));
        pool_payload
    }

    /// Note: Merely encoding a withdrawal message does not make a withdrawal
    /// in the current chain, and generics are not required.
    public fun withdraw_to(
        pool_chain_id: u16,
        pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let sender = types::convert_address_to_dola(tx_context::sender(ctx));
        let withdraw_pool = types::create_dola_address(pool_chain_id, pool_address);
        let pool_payload = codec_pool::encode_send_withdraw_payload(withdraw_pool, sender, app_id, app_payload);
        pool_payload
    }

    /// call by bridge
    public fun inner_withdraw<CoinType>(
        pool_approval: &PoolApproval,
        dola_contract: &DolaContract,
        pool: &mut Pool<CoinType>,
        user_addr: DolaAddress,
        amount: u64,
        pool_addr: DolaAddress,
        ctx: &mut TxContext
    ) {
        assert!(vector::contains(&pool_approval.spenders, &dola_contract::get_dola_contract(dola_contract)), EINVALID_WITHDRAW);
        let user_addr = types::convert_dola_to_address(user_addr);
        amount = unnormal_amount(pool, amount);
        let balance = balance::split(&mut pool.balance, amount);
        let coin = coin::from_balance(balance, ctx);
        assert!(types::get_native_dola_chain_id() == types::get_dola_chain_id(&pool_addr), EINVALID_CHAIN);
        assert!(
            types::get_dola_address(&pool_addr) == ascii::into_bytes(
                type_name::into_string(type_name::get<CoinType>())
            ),
            EINVALID_TOKEN
        );
        transfer::transfer(coin, user_addr);
    }

    public fun deposit_and_withdraw<DepositCoinType>(
        deposit_pool: &mut Pool<DepositCoinType>,
        deposit_coin: Coin<DepositCoinType>,
        withdraw_chain_id: u16,
        withdraw_pool_address: vector<u8>,
        app_id: u16,
        app_payload: vector<u8>,
        ctx: &mut TxContext
    ): vector<u8> {
        let amount = normal_amount(deposit_pool, coin::value(&deposit_coin));
        let depoist_user = types::convert_address_to_dola(tx_context::sender(ctx));
        let deposit_pool_address = types::convert_pool_to_dola<DepositCoinType>();

        balance::join(&mut deposit_pool.balance, coin::into_balance(deposit_coin));
        let withdraw_pool_address = types::create_dola_address(withdraw_chain_id, withdraw_pool_address);

        let pool_payload = codec_pool::encode_send_deposit_and_withdraw_payload(
            deposit_pool_address,
            depoist_user,
            amount,
            withdraw_pool_address,
            app_id,
            app_payload
        );
        pool_payload
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
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            amount,
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_amount, decoded_app_id, decoded_app_payload) = codec_pool::decode_send_deposit_payload(
            send_deposit_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode send_withdraw_payload
        let send_withdraw_payload = codec_pool::encode_send_withdraw_payload(
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_app_id, decoded_app_payload) = codec_pool::decode_send_withdraw_payload(
            send_withdraw_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode send_deposit_and_withdraw_payload
        let withdraw_pool = @0x33;
        let send_deposit_and_withdraw_payload = codec_pool::encode_send_deposit_and_withdraw_payload(
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            amount,
            types::convert_address_to_dola(withdraw_pool),
            app_id,
            app_payload
        );
        let (decoded_pool, decoded_user, decoded_amount, decoded_withdraw_pool, decoded_app_id, decoded_app_payload) = codec_pool::decode_send_deposit_and_withdraw_payload(
            send_deposit_and_withdraw_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
        assert!(decoded_amount == amount, 0);
        assert!(types::convert_dola_to_address(decoded_withdraw_pool) == withdraw_pool, 0);
        assert!(decoded_app_id == app_id, 0);
        assert!(decoded_app_payload == app_payload, 0);
        // test encode and decode receive_withdraw_payload
        let receive_withdraw_payload = codec_pool::encode_receive_withdraw_payload(
            0,
            0,
            types::convert_address_to_dola(pool),
            types::convert_address_to_dola(user),
            amount
        );
        let (_, _, decoded_pool, decoded_user, decoded_amount) = codec_pool::decode_receive_withdraw_payload(
            receive_withdraw_payload
        );
        assert!(types::convert_dola_to_address(decoded_pool) == pool, 0);
        assert!(types::convert_dola_to_address(decoded_user) == user, 0);
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
        let user_addr = @0xC;

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
            let pool_addr = types::convert_pool_to_dola<SUI>();

            let balance = balance::create_for_testing<SUI>(100);

            balance::join(&mut pool.balance, balance);

            assert!(balance::value(&pool.balance) == 100, 0);

            inner_withdraw<SUI>(&manager_cap, &mut pool, types::convert_address_to_dola(user_addr), 10, pool_addr, ctx);

            assert!(balance::value(&pool.balance) == 0, 0);
            delete_cap(&mut pool_info, manager_cap);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(pool_info);
        };
        test_scenario::end(scenario_val);
    }
}
