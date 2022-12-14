module lending::math {

    const RAY: u64 = 100000000;

    const SECONDS_PER_YEAR: u64 = 31536000;

    const SECONDS_PER_DAY: u64 = 86400;

    public fun ray_mul(a: u64, b: u64): u64 {
        ((a as u128) * (b as u128) / (RAY as u128) as u64)
    }

    public fun ray_div(a: u64, b: u64): u64 {
        (((a as u128) * (RAY as u128) / (b as u128)) as u64)
    }

    public fun calculate_average_liquidity(
        current_timestamp: u64,
        last_update_timestamp: u64,
        average_liquidity: u64,
        health_value: u64
    ): u64 {
        let delta_time = current_timestamp - last_update_timestamp;
        if (delta_time >= SECONDS_PER_DAY) {
            health_value
        } else {
            average_liquidity * delta_time / SECONDS_PER_DAY + health_value
        }
    }

    public fun calculate_compounded_interest(
        current_timestamp: u64,
        last_update_timestamp: u64,
        rate: u64,
    ): u64 {
        let exp = current_timestamp - last_update_timestamp;

        if (exp == 0) {
            return RAY
        };

        let exp_minus_one: u64;
        let exp_minus_two: u64;
        let base_power_two: u64;
        let base_power_three: u64;
        exp_minus_one = exp - 1;

        if (exp > 2) {
            exp_minus_two = exp - 2;
        }else {
            exp_minus_two = 0;
        };

        base_power_two = ray_mul(rate, rate) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);

        base_power_three = ray_mul(base_power_two, rate) / SECONDS_PER_YEAR;

        let second_term = exp * exp_minus_one * base_power_two;
        second_term = second_term / 2;
        let third_term = exp * exp_minus_one * exp_minus_two * base_power_three;
        third_term = third_term / 6;

        RAY + (rate * exp) / SECONDS_PER_YEAR + second_term + third_term
    }

    public fun calculate_linear_interest(
        current_timestamp: u64,
        last_update_timestamp: u64,
        rate: u64,
    ): u64 {
        let result = rate * (current_timestamp - last_update_timestamp);
        result = result / SECONDS_PER_YEAR;

        RAY + result
    }
}
