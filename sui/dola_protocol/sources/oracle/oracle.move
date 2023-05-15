// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Simply update the prices and get them for testing purposes only,
/// prices will be obtained from other oracles subsequently.
///
/// Note: This module is currently only used for testing
module dola_protocol::oracle {
    use sui::clock::{Self, Clock};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use pyth::hot_potato_vector;
    use pyth::i64;
    use pyth::price_info::PriceInfoObject;
    use pyth::pyth;
    use pyth::state::State as PythState;
    use wormhole::state::State as WormholeState;
    use wormhole::vaa;

    const MAX_PRICE_AGE: u64 = 60;

    const ENONEXISTENT_ORACLE: u64 = 0;

    const EALREADY_EXIST_ORACLE: u64 = 1;

    const ENOT_FRESH_PRICE: u64 = 2;

    struct OracleCap has key {
        id: UID
    }

    struct PriceOracle has key {
        id: UID,
        price_age: u64,
        // dola_pool_id => price
        price_oracles: Table<u16, Price>
    }

    struct Price has store {
        value: u256,
        // 2 decimals should be 100,
        decimal: u8,
        // last update timestamp
        last_update_timestamp: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(PriceOracle {
            id: object::new(ctx),
            price_age: MAX_PRICE_AGE,
            price_oracles: table::new(ctx)
        });
        transfer::transfer(OracleCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }

    public fun feed_token_price_by_pyth(
        wormhole_state: &WormholeState,
        pyth_state: &PythState,
        price_info_object: &mut PriceInfoObject,
        price_oracle: &mut PriceOracle,
        dola_pool_id: u16,
        vaa: vector<u8>,
        clock: &Clock,
        fee: Coin<SUI>
    ) {
        let verified_vaa = vaa::parse_and_verify(wormhole_state, vaa, clock);
        let price_info = pyth::create_price_infos_hot_potato(pyth_state, vector[verified_vaa], clock);
        let hot_potato_vector = pyth::update_single_price_feed(pyth_state, price_info, price_info_object, fee, clock);
        let current_timestamp = clock::timestamp_ms(clock) / 1000;
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, dola_pool_id), ENONEXISTENT_ORACLE);
        let price = table::borrow_mut(price_oracles, dola_pool_id);
        let pyth_price = pyth::get_price_no_older_than(price_info_object, clock, MAX_PRICE_AGE);
        hot_potato_vector::destroy(hot_potato_vector);

        let price_value = pyth::price::get_price(&pyth_price);
        let price_value = i64::get_magnitude_if_positive(&price_value);
        let expo = pyth::price::get_expo(&pyth_price);
        let expo = i64::get_magnitude_if_negative(&expo);

        price.value = (price_value as u256);
        price.decimal = (expo as u8);
        price.last_update_timestamp = current_timestamp;
    }

    public entry fun register_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        dola_pool_id: u16,
        token_price: u256,
        price_decimal: u8,
        clock: &Clock
    ) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(!table::contains(price_oracles, dola_pool_id), EALREADY_EXIST_ORACLE);
        table::add(price_oracles, dola_pool_id, Price {
            value: token_price,
            decimal: price_decimal,
            last_update_timestamp: clock::timestamp_ms(clock) / 1000
        })
    }

    public entry fun update_token_price(
        _: &OracleCap,
        price_oracle: &mut PriceOracle,
        dola_pool_id: u16,
        token_price: u256
    ) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, dola_pool_id), ENONEXISTENT_ORACLE);
        let price = table::borrow_mut(price_oracles, dola_pool_id);
        price.value = token_price;
    }

    public fun get_token_price(price_oracle: &mut PriceOracle, dola_pool_id: u16, clock: &Clock): (u256, u8) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, dola_pool_id), ENONEXISTENT_ORACLE);
        let price = table::borrow(price_oracles, dola_pool_id);
        let current_timestamp = clock::timestamp_ms(clock) / 1000;
        assert!(current_timestamp - price.last_update_timestamp < price_oracle.price_age, ENOT_FRESH_PRICE);
        (price.value, price.decimal)
    }

    public fun get_timestamp(sui_clock: &Clock): u256 {
        ((clock::timestamp_ms(sui_clock) / 1000) as u256)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        transfer::share_object(PriceOracle {
            id: object::new(ctx),
            price_age: MAX_PRICE_AGE,
            price_oracles: table::new(ctx)
        });
        transfer::transfer(OracleCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }
}
