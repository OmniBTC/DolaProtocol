// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module dola_protocol::rates {
    use dola_protocol::lending_core_storage::{Self as storage, Storage};
    use dola_protocol::ray_math as math;

    const SECONDS_PER_YEAR: u256 = 31536000;

    const SECONDS_PER_DAY: u256 = 86400;

    /// === Helper Functions ===

    /// Calculating utilization using liquidity and debt. Liquidity is the current liquidity plus the
    /// liquidity of the current operation
    public fun calculate_utilization(storage: &mut Storage, dola_pool_id: u16, liquidity: u256): u256 {
        let scale_balance = storage::get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let cur_borrow_index = storage::get_borrow_index(storage, dola_pool_id);
        let debt = math::ray_mul(scale_balance, cur_borrow_index);
        if (debt + liquidity == 0) {
            0
        } else {
            math::ray_div(debt, debt + liquidity)
        }
    }

    public fun calculate_borrow_rate(storage: &mut Storage, dola_pool_id: u16, liquidity: u256): u256 {
        let utilization = calculate_utilization(storage, dola_pool_id, liquidity);
        let (base_borrow_rate, borrow_rate_slope1, borrow_rate_slope2, optimal_utilization) = storage::get_borrow_rate_factors(
            storage,
            dola_pool_id
        );
        if (utilization < optimal_utilization) {
            base_borrow_rate + math::ray_mul(math::ray_div(utilization, optimal_utilization), borrow_rate_slope1)
        } else {
            base_borrow_rate + borrow_rate_slope1 + math::ray_mul(
                borrow_rate_slope2,
                math::ray_div(utilization - optimal_utilization, math::ray() - optimal_utilization)
            )
        }
    }

    public fun calculate_liquidity_rate(
        storage: &mut Storage,
        dola_pool_id: u16,
        borrow_rate: u256,
        liquidity: u256
    ): u256 {
        let utilization = calculate_utilization(storage, dola_pool_id, liquidity);
        let treasury_factor = storage::get_treasury_factor(storage, dola_pool_id);
        math::ray_mul(borrow_rate, math::ray_mul(utilization, math::ray() - treasury_factor))
    }

    public fun calculate_average_liquidity(
        current_timestamp: u256,
        last_update_timestamp: u256,
        average_liquidity: u256,
        health_value: u256
    ): u256 {
        let delta_time = current_timestamp - last_update_timestamp;
        let cur_duration = math::min(delta_time, SECONDS_PER_DAY);
        let pre_duration = SECONDS_PER_DAY - cur_duration;
        (average_liquidity * pre_duration + health_value * cur_duration) / SECONDS_PER_DAY
    }

    public fun calculate_compounded_interest(
        current_timestamp: u256,
        last_update_timestamp: u256,
        rate: u256,
    ): u256 {
        let exp = current_timestamp - last_update_timestamp;

        if (exp == 0) {
            return math::ray()
        };

        let exp_minus_one: u256;
        let exp_minus_two: u256;
        let base_power_two: u256;
        let base_power_three: u256;
        exp_minus_one = exp - 1;

        if (exp > 2) {
            exp_minus_two = exp - 2;
        }else {
            exp_minus_two = 0;
        };

        base_power_two = math::ray_mul(rate, rate) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);

        base_power_three = math::ray_mul(base_power_two, rate) / SECONDS_PER_YEAR;

        let second_term = exp * exp_minus_one * base_power_two;
        second_term = second_term / 2;
        let third_term = exp * exp_minus_one * exp_minus_two * base_power_three;
        third_term = third_term / 6;

        math::ray() + (rate * exp) / SECONDS_PER_YEAR + second_term + third_term
    }

    public fun calculate_linear_interest(
        current_timestamp: u256,
        last_update_timestamp: u256,
        rate: u256,
    ): u256 {
        let result = rate * (current_timestamp - last_update_timestamp);
        result = result / SECONDS_PER_YEAR;

        math::ray() + result
    }
}
