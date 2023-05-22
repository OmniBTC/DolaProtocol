// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Simply update the prices and get them for testing purposes only,
/// prices will be obtained from other oracles subsequently.
///
/// Note: This module is currently only used for testing
module dola_protocol::oracle {
    use std::vector;

    use sui::clock::{Self, Clock};
    use sui::coin::Coin;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use dola_protocol::genesis::{Self, GovernanceCap, GovernanceGenesis};
    use pyth::hot_potato_vector;
    use pyth::i64;
    use pyth::price_identifier::{Self, PriceIdentifier};
    use pyth::price_info::{Self, PriceInfoObject};
    use pyth::pyth;
    use pyth::state::State as PythState;
    use pyth_wormhole::state::State as WormholeState;
    use pyth_wormhole::vaa;

    const MINUATE: u64 = 60;

    const HOUR: u64 = 60 * 60;

    const ENONEXISTENT_ORACLE: u64 = 0;

    const EALREADY_EXIST_ORACLE: u64 = 1;

    const ENOT_FRESH_PRICE: u64 = 2;

    const ENOT_RECENT_PRICE: u64 = 3;

    const EWRONG_FEED_TOKEN: u64 = 4;

    struct PriceOracle has key {
        id: UID,
        // price guard period
        price_guard_time: u64,
        // the maximum period of validity of the price when executing the transaction
        price_fresh_time: u64,
        // dola_pool_id => price_identifier
        price_identifiers: Table<u16, PriceIdentifier>,
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
            price_guard_time: HOUR,
            price_fresh_time: MINUATE,
            price_identifiers: table::new(ctx),
            price_oracles: table::new(ctx)
        });
    }

    /// === View Functions ===

    /// Use the price for at least one hour to display the user's status.
    public fun get_token_price(price_oracle: &mut PriceOracle, dola_pool_id: u16): (u256, u8, u64) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(table::contains(price_oracles, dola_pool_id), ENONEXISTENT_ORACLE);
        let price = table::borrow(price_oracles, dola_pool_id);

        (price.value, price.decimal, price.last_update_timestamp)
    }

    /// === Governance Functions ===

    public fun set_price_guard_time(
        _: &GovernanceCap,
        price_oracle: &mut PriceOracle,
        price_guard_time: u64
    ) {
        price_oracle.price_guard_time = price_guard_time;
    }

    public fun set_price_fresh_time(
        _: &GovernanceCap,
        price_oracle: &mut PriceOracle,
        price_fresh_time: u64
    ) {
        price_oracle.price_fresh_time = price_fresh_time;
    }

    public fun register_token_price(
        _: &GovernanceCap,
        price_oracle: &mut PriceOracle,
        feed_id: vector<u8>,
        dola_pool_id: u16,
        price_value: u256,
        price_decimal: u8,
        clock: &Clock
    ) {
        let price_oracles = &mut price_oracle.price_oracles;
        assert!(!table::contains(price_oracles, dola_pool_id), EALREADY_EXIST_ORACLE);
        let price_identifier = price_identifier::from_byte_vec(feed_id);
        let price_identifiers = &mut price_oracle.price_identifiers;
        assert!(
            !table::contains(price_identifiers, dola_pool_id),
            EALREADY_EXIST_ORACLE
        );
        table::add(price_identifiers, dola_pool_id, price_identifier);
        table::add(price_oracles, dola_pool_id, Price {
            value: price_value,
            decimal: price_decimal,
            last_update_timestamp: clock::timestamp_ms(clock) / 1000
        })
    }

    /// === Helper Functions ===

    /// When doing withdraw or borrow or liquidate, use the latest price.
    public fun check_fresh_price(price_oracle: &mut PriceOracle, dola_pool_ids: vector<u16>, clock: &Clock) {
        let price_oracles = &mut price_oracle.price_oracles;
        let current_timestamp = clock::timestamp_ms(clock) / 1000;

        let index = 0;
        while (index < vector::length(&dola_pool_ids)) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, index);
            let price = table::borrow(price_oracles, *dola_pool_id);
            // check fresh price
            assert!(current_timestamp - price.last_update_timestamp < price_oracle.price_fresh_time, ENOT_FRESH_PRICE);
            index = index + 1;
        }
    }

    public fun check_guard_price(price_oracle: &mut PriceOracle, dola_pool_ids: vector<u16>, clock: &Clock) {
        let price_oracles = &mut price_oracle.price_oracles;
        let current_timestamp = clock::timestamp_ms(clock) / 1000;

        let index = 0;
        while (index < vector::length(&dola_pool_ids)) {
            let dola_pool_id = vector::borrow(&dola_pool_ids, index);
            let price = table::borrow(price_oracles, *dola_pool_id);
            // check price guard time
            assert!(current_timestamp - price.last_update_timestamp < price_oracle.price_guard_time, ENOT_RECENT_PRICE);
            index = index + 1;
        }
    }

    /// === Entry Functions ===

    public fun feed_token_price_by_pyth(
        genesis: &GovernanceGenesis,
        wormhole_state: &mut WormholeState,
        pyth_state: &mut PythState,
        price_info_object: &mut PriceInfoObject,
        price_oracle: &mut PriceOracle,
        dola_pool_id: u16,
        vaa: vector<u8>,
        clock: &Clock,
        fee: Coin<SUI>
    ) {
        // Check current protocol version
        genesis::check_latest_version(genesis);

        // Check feed token is correct
        assert!(table::contains(&price_oracle.price_identifiers, dola_pool_id), ENONEXISTENT_ORACLE);
        let price_idetifiers = &mut price_oracle.price_identifiers;
        let price_identifier = table::borrow(price_idetifiers, dola_pool_id);
        let price_info = price_info::get_price_info_from_price_info_object(price_info_object);
        let pyth_price_identifier = price_info::get_price_identifier(&price_info);
        assert!(price_identifier == &pyth_price_identifier, EWRONG_FEED_TOKEN);

        let verified_vaa = vaa::parse_and_verify(wormhole_state, vaa, clock);
        let price_info = pyth::create_price_infos_hot_potato(pyth_state, vector[verified_vaa], clock);
        let hot_potato_vector = pyth::update_single_price_feed(pyth_state, price_info, price_info_object, fee, clock);
        let current_timestamp = clock::timestamp_ms(clock) / 1000;
        let price_oracles = &mut price_oracle.price_oracles;
        let price = table::borrow_mut(price_oracles, dola_pool_id);

        // get the price of the lastest minute
        let pyth_price = pyth::get_price_no_older_than(price_info_object, clock, MINUATE);
        hot_potato_vector::destroy(hot_potato_vector);

        let price_value = pyth::price::get_price(&pyth_price);
        let price_value = i64::get_magnitude_if_positive(&price_value);
        let expo = pyth::price::get_expo(&pyth_price);
        let expo = i64::get_magnitude_if_negative(&expo);

        price.value = (price_value as u256);
        price.decimal = (expo as u8);
        price.last_update_timestamp = current_timestamp;
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        transfer::share_object(PriceOracle {
            id: object::new(ctx),
            price_guard_time: HOUR,
            price_fresh_time: MINUATE,
            price_identifiers: table::new(ctx),
            price_oracles: table::new(ctx)
        });
    }

    #[test_only]
    public fun update_token_price(oracle: &mut PriceOracle, dola_pool_id: u16, price_value: u256) {
        let price_oracles = &mut oracle.price_oracles;
        let price = table::borrow_mut(price_oracles, dola_pool_id);
        price.value = price_value;
    }
}
