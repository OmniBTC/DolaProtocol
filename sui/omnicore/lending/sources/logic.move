module lending::logic {
    use std::vector;

    use dola_types::types::{DolaAddress, decode_dola_address, encode_dola_address};
    use lending::math::{Self, calculate_compounded_interest, calculate_linear_interest, ray_mul, ray_div};
    use lending::rates;
    use lending::scaled_balance::{Self, balance_of};
    use lending::storage::{Self, StorageCap, Storage, get_liquidity_index, get_user_collaterals, get_user_scaled_otoken, get_user_loans, get_user_scaled_dtoken, add_user_collateral, add_user_loan, get_otoken_scaled_total_supply, get_borrow_index, get_dtoken_scaled_total_supply, get_app_id, remove_user_collateral, remove_user_loan, get_collateral_coefficient, get_borrow_coefficient, exist_user_info, get_user_average_liquidity, get_reserve_treasury};
    use oracle::oracle::{get_token_price, PriceOracle, get_timestamp};
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use serde::serde::{deserialize_u64, deserialize_u8, vector_slice, deserialize_u16, serialize_u64, serialize_u16, serialize_vector, serialize_u8};
    use sui::math::{pow, min};

    const U64_MAX: u64 = 0xFFFFFFFFFFFFFFFF;

    const RAY: u64 = 100000000;

    /// 20%
    const MAX_DISCOUNT: u64 = 20000000;

    /// HF 1.25
    const TARGET_HEALTH_FACTOR: u64 = 125000000;

    const ECOLLATERAL_AS_LOAN: u64 = 0;

    const ENOT_HEALTH: u64 = 1;

    const EIS_HEALTH: u64 = 2;

    const ENOT_COLLATERAL: u64 = 3;

    const ENOT_LOAN: u64 = 4;

    const ENOT_ENOUGH_OTOKEN: u64 = 5;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 6;

    const EINVALID_LENGTH: u64 = 7;

    const EZERO_APP_LIQUIDITY: u64 = 8;

    public fun execute_liquidate(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: u64,
        violator: u64,
        collateral: u16,
        loan: u16,
        repay_debt: u64,
    ): (u64, u64) {
        update_state(cap, storage, oracle, loan);
        update_state(cap, storage, oracle, collateral);
        update_average_liquidity(cap, storage, oracle, liquidator);
        assert!(is_collateral(storage, violator, collateral), ENOT_COLLATERAL);
        assert!(is_loan(storage, violator, loan), ENOT_LOAN);
        assert!(!is_health(storage, oracle, violator), EIS_HEALTH);
        let (max_liquidable_collateral, max_liquidable_debt) = calculate_max_liquidation(
            storage,
            oracle,
            liquidator,
            violator,
            collateral,
            loan
        );

        let treasury_factor = storage::get_treasury_factor(storage, collateral);

        let (actual_liquidable_collateral, actual_liquidable_debt, liquidator_acquired_collateral, treasury_reserved_collateral, excess_repay_amount) = calculate_actual_liquidation(
            max_liquidable_collateral,
            max_liquidable_debt,
            repay_debt,
            treasury_factor
        );

        let treasury = get_reserve_treasury(storage, collateral);
        burn_dtoken(cap, storage, violator, loan, actual_liquidable_debt);
        burn_otoken(cap, storage, violator, collateral, actual_liquidable_collateral);
        mint_otoken(cap, storage, treasury, collateral, treasury_reserved_collateral);
        update_interest_rate(cap, pool_manager_info, storage, collateral);
        update_interest_rate(cap, pool_manager_info, storage, loan);
        update_average_liquidity(cap, storage, oracle, violator);
        (liquidator_acquired_collateral, excess_repay_amount)
    }

    public fun execute_supply(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        assert!(!is_loan(storage, dola_user_id, dola_pool_id), ENOT_LOAN);
        update_state(cap, storage, oracle, dola_pool_id);
        mint_otoken(cap, storage, dola_user_id, dola_pool_id, token_amount);
        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);
        if (!is_collateral(storage, dola_user_id, dola_pool_id)) {
            add_user_collateral(cap, storage, oracle, dola_user_id, dola_pool_id);
        };
        update_average_liquidity(cap, storage, oracle, dola_user_id);
    }

    public fun execute_withdraw(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        withdraw_amount: u64,
    ) {
        update_state(cap, storage, oracle, dola_pool_id);
        // check otoken amount
        let otoken_amount = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        assert!(withdraw_amount <= otoken_amount, ENOT_ENOUGH_OTOKEN);
        burn_otoken(cap, storage, dola_user_id, dola_pool_id, withdraw_amount);

        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);

        assert!(is_health(storage, oracle, dola_user_id), ENOT_HEALTH);
        if (withdraw_amount == otoken_amount) {
            remove_user_collateral(cap, storage, dola_user_id, dola_pool_id);
        };
        update_average_liquidity(cap, storage, oracle, dola_user_id);
    }

    public fun execute_borrow(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        borrow_pool_id: u16,
        borrow_amount: u64,
    ) {
        update_state(cap, storage, oracle, borrow_pool_id);

        assert!(!is_collateral(storage, dola_user_id, borrow_pool_id), ECOLLATERAL_AS_LOAN);
        if (!is_loan(storage, dola_user_id, borrow_pool_id)) {
            add_user_loan(cap, storage, oracle, dola_user_id, borrow_pool_id);
        };
        mint_dtoken(cap, storage, dola_user_id, borrow_pool_id, borrow_amount);

        let liquidity = pool_manager::get_app_liquidity(
            pool_manager_info,
            borrow_pool_id,
            get_app_id(storage)
        );
        assert!((borrow_amount as u128) <= liquidity, ENOT_ENOUGH_LIQUIDITY);
        assert!(is_health(storage, oracle, dola_user_id), ENOT_HEALTH);
        update_interest_rate(cap, pool_manager_info, storage, borrow_pool_id);
        update_average_liquidity(cap, storage, oracle, dola_user_id);
    }

    public fun execute_repay(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        repay_amount: u64,
    ) {
        update_state(cap, storage, oracle, dola_pool_id);
        let debt = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let repay_debt = min(repay_amount, debt);
        burn_dtoken(cap, storage, dola_user_id, dola_pool_id, repay_debt);
        if (repay_amount >= debt) {
            remove_user_loan(cap, storage, dola_user_id, dola_pool_id);
            let excess_repay_amount = repay_amount - debt;
            if (excess_repay_amount > 0) {
                mint_otoken(cap, storage, dola_user_id, dola_pool_id, excess_repay_amount);
                add_user_collateral(cap, storage, oracle, dola_user_id, dola_pool_id);
            }
        };
        update_interest_rate(cap, pool_manager_info, storage, dola_pool_id);
        update_average_liquidity(cap, storage, oracle, dola_user_id);
    }

    public fun is_health(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): bool {
        user_health_factor(storage, oracle, dola_user_id) >= RAY
    }

    public fun is_collateral(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        if (exist_user_info(storage, dola_user_id)) {
            let collaterals = get_user_collaterals(storage, dola_user_id);
            vector::contains(&collaterals, &dola_pool_id)
        } else {
            false
        }
    }

    public fun is_loan(storage: &mut Storage, dola_user_id: u64, dola_pool_id: u16): bool {
        if (exist_user_info(storage, dola_user_id)) {
            let loans = get_user_loans(storage, dola_user_id);
            vector::contains(&loans, &dola_pool_id)
        } else {
            false
        }
    }

    public fun user_health_factor(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): u64 {
        let health_collateral_value = user_health_collateral_value(storage, oracle, dola_user_id);
        let health_loan_value = user_health_loan_value(storage, oracle, dola_user_id);
        if (health_loan_value > 0) {
            ray_div(health_collateral_value, health_loan_value)
        } else {
            U64_MAX
        }
    }

    public fun user_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let balance = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((balance as u128) * (price as u128) / (pow(10, decimal) as u128)) as u64)
    }

    public fun user_collateral_balance(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let scaled_balance = get_user_scaled_otoken(storage, dola_user_id, dola_pool_id);
        let current_index = get_liquidity_index(storage, dola_pool_id);
        balance_of(scaled_balance, current_index)
    }

    public fun user_loan_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let balance = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((balance as u128) * (price as u128) / (pow(10, decimal) as u128)) as u64)
    }

    public fun user_loan_balance(
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16
    ): u64 {
        let scaled_balance = get_user_scaled_dtoken(storage, dola_user_id, dola_pool_id);
        let current_index = get_liquidity_index(storage, dola_pool_id);
        balance_of(scaled_balance, current_index)
    }

    public fun user_health_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u64 {
        let collaterals = get_user_collaterals(storage, dola_user_id);
        let length = vector::length(&collaterals);
        let value = 0;
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let collateral_coefficient = get_collateral_coefficient(storage, *collateral);
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            value = value + ray_mul(collateral_value, collateral_coefficient);
            i = i + 1;
        };
        value
    }

    public fun user_health_loan_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u64 {
        let loans = get_user_loans(storage, dola_user_id);
        let length = vector::length(&loans);
        let value = 0;
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let borrow_coefficient = get_borrow_coefficient(storage, *loan);
            let loan_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            value = value + ray_mul(loan_value, borrow_coefficient);
            i = i + 1;
        };
        value
    }

    public fun user_total_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ): u64 {
        let collaterals = get_user_collaterals(storage, dola_user_id);
        let length = vector::length(&collaterals);
        let value = 0;
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            value = value + collateral_value;
            i = i + 1;
        };
        value
    }

    public fun user_total_loan_value(storage: &mut Storage, oracle: &mut PriceOracle, dola_user_id: u64): u64 {
        let loans = get_user_loans(storage, dola_user_id);
        let length = vector::length(&loans);
        let value = 0;
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let loan_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            value = value + loan_value;
            i = i + 1;
        };
        value
    }

    public fun calculate_value(oracle: &mut PriceOracle, dola_pool_id: u16, amount: u64): u64 {
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((amount as u128) * (price as u128) / (pow(10, decimal) as u128)) as u64)
    }

    public fun calculate_amount(oracle: &mut PriceOracle, dola_pool_id: u16, value: u64): u64 {
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        (((value as u128) * (pow(10, decimal) as u128)) / (price as u128) as u64)
    }

    public fun calculate_liquidation_base_discount(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        violator: u64
    ): u64 {
        let health_collateral_value = user_health_collateral_value(storage, oracle, violator);
        let health_loan_value = user_health_loan_value(storage, oracle, violator);
        // health_collateral_value < health_loan_value
        RAY - ray_div(health_collateral_value, health_loan_value)
    }

    public fun calculate_liquidation_discount(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: u64,
        violator: u64,
        collateral: u16,
        loan: u16
    ): u64 {
        let base_discount = calculate_liquidation_base_discount(storage, oracle, violator);
        let average_liquidity = get_user_average_liquidity(storage, liquidator);
        let health_loan_value = user_health_loan_value(storage, oracle, violator);
        let borrow_coefficient = get_borrow_coefficient(storage, loan);
        let discount_booster = ray_div(average_liquidity, 5 * ray_mul(health_loan_value, borrow_coefficient));
        discount_booster = min(discount_booster, RAY) + RAY;
        let treasury_factor = storage::get_treasury_factor(storage, collateral);
        let liquidation_discount = ray_mul(base_discount, discount_booster) + treasury_factor;
        min(liquidation_discount, MAX_DISCOUNT)
    }

    public fun calculate_max_liquidation(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: u64,
        violator: u64,
        collateral: u16,
        loan: u16
    ): (u64, u64) {
        let liquidation_discount = calculate_liquidation_discount(
            storage,
            oracle,
            liquidator,
            violator,
            collateral,
            loan
        );

        let health_collateral_value = user_health_collateral_value(storage, oracle, violator);
        let health_loan_value = user_health_loan_value(storage, oracle, violator);

        let borrow_coefficient = get_borrow_coefficient(storage, loan);
        let collateral_coefficient = get_collateral_coefficient(storage, collateral);

        let target_health_value = ray_mul(health_loan_value, TARGET_HEALTH_FACTOR) - health_collateral_value;
        let target_coefficient = ray_mul(
            ray_mul(TARGET_HEALTH_FACTOR, RAY - liquidation_discount),
            borrow_coefficient
        ) - collateral_coefficient;

        let max_liquidable_collateral_value = ray_div(target_health_value, target_coefficient);
        let user_max_collateral_value = user_collateral_value(storage, oracle, violator, collateral);
        let collateral_ratio = ray_div(user_max_collateral_value, max_liquidable_collateral_value);

        let max_liquidable_debt_vaule = ray_mul(max_liquidable_collateral_value, RAY - liquidation_discount);
        let user_max_debt_value = user_loan_value(storage, oracle, violator, loan);
        let debt_ratio = ray_div(user_max_debt_value, max_liquidable_debt_vaule);

        let ratio = min(min(collateral_ratio, debt_ratio), RAY);
        let max_liquidable_collateral = calculate_amount(
            oracle,
            collateral,
            ray_mul(max_liquidable_collateral_value, ratio)
        );
        let max_liquidable_debt = calculate_amount(oracle, loan, ray_mul(max_liquidable_debt_vaule, ratio));
        (max_liquidable_collateral, max_liquidable_debt)
    }

    public fun calculate_actual_liquidation(
        max_liquidable_collateral: u64,
        max_liquidable_debt: u64,
        repay_debt: u64,
        treasury_factor: u64
    ): (u64, u64, u64, u64, u64) {
        let excess_repay_amount;
        let actual_liquidable_collateral;
        let actual_liquidable_debt;

        if (repay_debt >= max_liquidable_debt) {
            excess_repay_amount = repay_debt - max_liquidable_debt;
            actual_liquidable_collateral = max_liquidable_collateral;
            actual_liquidable_debt = max_liquidable_debt;
        } else {
            excess_repay_amount = 0;
            actual_liquidable_debt = repay_debt;
            actual_liquidable_collateral = ray_mul(
                max_liquidable_collateral,
                ray_div(actual_liquidable_debt, max_liquidable_debt)
            );
        };

        let liquidator_acquired_collateral = ray_mul(actual_liquidable_collateral, RAY - treasury_factor);
        let treasury_reserved_collateral = ray_mul(actual_liquidable_collateral, treasury_factor);
        (actual_liquidable_collateral, actual_liquidable_debt, liquidator_acquired_collateral, treasury_reserved_collateral, excess_repay_amount)
    }

    public fun total_otoken_supply(storage: &mut Storage, dola_pool_id: u16): u128 {
        let scaled_total_otoken_supply = get_otoken_scaled_total_supply(storage, dola_pool_id);
        let current_index = get_liquidity_index(storage, dola_pool_id);
        scaled_total_otoken_supply * (current_index as u128) / (RAY as u128)
    }

    public fun total_dtoken_supply(storage: &mut Storage, dola_pool_id: u16): u128 {
        let scaled_total_dtoken_supply = get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let current_index = get_borrow_index(storage, dola_pool_id);
        scaled_total_dtoken_supply * (current_index as u128) / (RAY as u128)
    }

    public fun mint_otoken(
        cap: &StorageCap, // todo! Where manage this?
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::mint_otoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun burn_otoken(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::burn_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::burn_otoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun mint_dtoken(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::mint_dtoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun burn_dtoken(
        cap: &StorageCap,
        storage: &mut Storage,
        dola_user_id: u64,
        dola_pool_id: u16,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::burn_scaled(token_amount, get_liquidity_index(storage, dola_pool_id));
        storage::burn_dtoken_scaled(
            cap,
            storage,
            dola_pool_id,
            dola_user_id,
            scaled_amount
        );
    }

    public fun update_average_liquidity(
        cap: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ) {
        if (exist_user_info(storage, dola_user_id)) {
            let current_timestamp = get_timestamp(oracle);
            let last_update_timestamp = storage::get_user_last_timestamp(storage, dola_user_id);
            let health_collateral_value = user_health_collateral_value(storage, oracle, dola_user_id);
            let health_loan_value = user_health_loan_value(storage, oracle, dola_user_id);
            if (health_collateral_value > health_loan_value) {
                let health_value = health_collateral_value - health_loan_value;
                let average_liquidity = storage::get_user_average_liquidity(storage, dola_user_id);
                let new_average_liquidity = math::calculate_average_liquidity(
                    current_timestamp,
                    last_update_timestamp,
                    average_liquidity,
                    health_value
                );
                storage::update_user_average_liquidity(cap, storage, oracle, dola_user_id, new_average_liquidity);
            } else {
                storage::update_user_average_liquidity(cap, storage, oracle, dola_user_id, 0);
            }
        }
    }

    public fun update_state(
        cap: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_pool_id: u16,
    ) {
        // todo: use sui timestamp
        let current_timestamp = get_timestamp(oracle);

        let last_update_timestamp = storage::get_last_update_timestamp(storage, dola_pool_id);
        let dtoken_scaled_total_supply = storage::get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let current_borrow_index = storage::get_borrow_index(storage, dola_pool_id);
        let current_liquidity_index = storage::get_liquidity_index(storage, dola_pool_id);

        let treasury_factor = storage::get_treasury_factor(storage, dola_pool_id);

        let new_borrow_index = math::ray_mul(calculate_compounded_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_borrow_rate(storage, dola_pool_id)
        ), current_borrow_index) ;

        let new_liquidity_index = math::ray_mul(calculate_linear_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_liquidity_rate(storage, dola_pool_id)
        ), current_liquidity_index);

        let mint_to_treasury = ((dtoken_scaled_total_supply *
            ((new_borrow_index - current_borrow_index) as u128) /
            (RAY as u128) * (treasury_factor as u128) / (RAY as u128)) as u64);
        storage::update_state(cap, storage, dola_pool_id, new_borrow_index, new_liquidity_index, mint_to_treasury);
    }

    public fun update_interest_rate(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16,
    ) {
        let liquidity = pool_manager::get_app_liquidity(
            pool_manager_info,
            dola_pool_id,
            get_app_id(storage)
        );
        assert!(liquidity > 0, EZERO_APP_LIQUIDITY);
        let borrow_rate = rates::calculate_borrow_rate(storage, dola_pool_id, liquidity);
        let liquidity_rate = rates::calculate_liquidity_rate(storage, dola_pool_id, borrow_rate, liquidity);
        storage::update_interest_rate(cap, storage, dola_pool_id, borrow_rate, liquidity_rate);
    }

    public fun encode_app_payload(
        call_type: u8,
        amount: u64,
        receiver: DolaAddress,
        liquidate_user_id: u64
    ): vector<u8> {
        let payload = vector::empty<u8>();
        serialize_u64(&mut payload, amount);
        let receiver = encode_dola_address(receiver);
        serialize_u16(&mut payload, (vector::length(&receiver) as u16));
        serialize_vector(&mut payload, receiver);
        serialize_u64(&mut payload, liquidate_user_id);
        serialize_u8(&mut payload, call_type);
        payload
    }

    public fun decode_app_payload(app_payload: vector<u8>): (u8, u64, DolaAddress, u64) {
        let index = 0;
        let data_len;

        data_len = 8;
        let amount = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 2;
        let receive_length = deserialize_u16(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = (receive_length as u64);
        let receiver = decode_dola_address(vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 8;
        let liquidate_user_id = deserialize_u64(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        data_len = 1;
        let call_type = deserialize_u8(&vector_slice(&app_payload, index, index + data_len));
        index = index + data_len;

        assert!(index == vector::length(&app_payload), EINVALID_LENGTH);

        (call_type, amount, receiver, liquidate_user_id)
    }
}
