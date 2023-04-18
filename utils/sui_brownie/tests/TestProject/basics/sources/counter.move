// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This example demonstrates a basic use of a shared object.
/// Rules:
/// - anyone can create and share a counter
/// - everyone can increment a counter by 1
/// - the owner of the counter can reset it to any value
module basics::counter {
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use sui::balance;
    use sui::balance::Supply;
    use sui::coin;
    use sui::coin::Coin;

    struct USDT has drop {}

    /// A shared counter.
    struct Counter has key {
        id: UID,
        owner: address,
        value: u64
    }

    struct Data<T> has drop {
        value: T
    }

    struct Bag<phantom T> has key {
        id: UID,
        supply: Supply<T>
    }

    public fun owner(counter: &Counter): address {
        counter.owner
    }

    public fun value(counter: &Counter): u64 {
        counter.value
    }

    /// Create and share a Counter object.
    public entry fun create(ctx: &mut TxContext) {
        let supply = balance::create_supply(USDT {});
        let minted_balance = balance::increase_supply(
            &mut supply,
            10000000000
        );
        transfer::public_transfer(
            coin::from_balance(minted_balance, ctx),
            tx_context::sender(ctx)
        );
        let minted_balance = balance::increase_supply(
            &mut supply,
            500000
        );
        transfer::public_transfer(
            coin::from_balance(minted_balance, ctx),
            tx_context::sender(ctx)
        );
        transfer::transfer(Bag {
            id: object::new(ctx),
            supply
        }, tx_context::sender(ctx));
        transfer::transfer(Counter {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            value: 1
        }, tx_context::sender(ctx));
        transfer::share_object(Counter {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            value: 0
        })
    }

    public fun get_value(counter: &Counter): u64 {
        counter.value
    }

    public fun get_counter(counter: Counter): Counter {
        counter
    }

    public fun increment_counter(counter: &mut Counter): &mut Counter {
        counter.value = counter.value + 1;
        counter
    }

    public fun test_data_type<T: drop>(
        _v0: &Data<u8>,
        _v1: &Data<address>,
        _v2: &Data<bool>,
        _v3: &Data<Counter>,
        _v4: &Data<T>,
        _v5: &vector<u8>,
        _v6: &vector<address>,
        _v7: &vector<bool>,
        _v8: &vector<Counter>,
        _v9: &vector<T>,
        _v10: &Data<Data<u8>>,
        _v11: &vector<vector<T>>
    ) {}

    public entry fun test_vec_object<T: drop>(
        v0: vector<Coin<T>>,
        _amount: u64,
        ctx: &mut TxContext
    ) {
        while (!vector::is_empty(&v0)) {
            transfer::public_transfer(vector::pop_back(&mut v0), tx_context::sender(ctx));
        };
        vector::destroy_empty(v0);
    }

    /// Increment a counter by 1.
    public entry fun increment(counter: &mut Counter) {
        counter.value = counter.value + 1;
    }

    /// Set value (only runnable by the Counter owner)
    public entry fun set_value(counter: &mut Counter, value: u64, ctx: &TxContext) {
        assert!(counter.owner == tx_context::sender(ctx), 0);
        counter.value = value;
    }

    public entry fun test_param<T: drop>(
        counter: &mut Counter,
        value: vector<u64>,
        index: u64,
        _v0: T,
        _v1: vector<T>,
        _v2: vector<vector<T>>,
        _v3: vector<vector<u8>>
    ) {
        counter.value = *vector::borrow(&value, index);
    }

    /// Assert a value for the counter.
    public entry fun assert_value(counter: &Counter, value: u64) {
        assert!(counter.value == value, 0)
    }
}

#[test_only]
module basics::counter_test {
    use sui::test_scenario;
    use basics::counter;

    #[test]
    fun test_counter() {
        let owner = @0xC0FFEE;
        let user1 = @0xA1;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, owner);
        {
            counter::create(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, user1);
        {
            let counter_val = test_scenario::take_shared<counter::Counter>(scenario);
            let counter = &mut counter_val;

            assert!(counter::owner(counter) == owner, 0);
            assert!(counter::value(counter) == 0, 1);

            counter::increment(counter);
            counter::increment(counter);
            counter::increment(counter);
            test_scenario::return_shared(counter_val);
        };

        test_scenario::next_tx(scenario, owner);
        {
            let counter_val = test_scenario::take_shared<counter::Counter>(scenario);
            let counter = &mut counter_val;

            assert!(counter::owner(counter) == owner, 0);
            assert!(counter::value(counter) == 3, 1);

            counter::set_value(counter, 100, test_scenario::ctx(scenario));

            test_scenario::return_shared(counter_val);
        };

        test_scenario::next_tx(scenario, user1);
        {
            let counter_val = test_scenario::take_shared<counter::Counter>(scenario);
            let counter = &mut counter_val;

            assert!(counter::owner(counter) == owner, 0);
            assert!(counter::value(counter) == 100, 1);

            counter::increment(counter);

            assert!(counter::value(counter) == 101, 2);

            test_scenario::return_shared(counter_val);
        };
        test_scenario::end(scenario_val);
    }
}
