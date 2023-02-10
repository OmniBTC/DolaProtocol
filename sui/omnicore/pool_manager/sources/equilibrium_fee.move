module pool_manager::equilibrium_fee {

    use pool_manager::math::{ray_div, ray, ray_mul, ray_ln2, ray_log2};

    /// Equilibrium fees are charged when liquidity is less than 60% of the target liquidity.
    const ALPHA_1: u256 = 600000000000000000000000000;

    /// Fee ratio 0.05%
    const LAMBDA_1: u256 = 500000000000000000000000;

    public fun calculate_expected_ratio(total_weight: u16, weight: u8): u256 {
        ray_div((weight as u256), (total_weight as u256))
    }

    public fun calculate_equilibrium_fee(
        total_liquidity: u256,
        current_liquidity: u256,
        withdraw_amount: u256,
        expected_ratio: u256
    ): u256 {
        let current_ratio = ray_div(
            ray_div(current_liquidity - withdraw_amount, total_liquidity - withdraw_amount),
            expected_ratio
        );

        let n_start = if (current_liquidity > ray_mul(ray_mul(total_liquidity, expected_ratio), ALPHA_1)) {
            ray_div(
                current_liquidity - ray_mul(ray_mul(total_liquidity, ALPHA_1), expected_ratio),
                ray() - ray_mul(ALPHA_1, expected_ratio)
            )
        } else { 0 };

        if (current_ratio > ALPHA_1) {
            0
        } else {
            let fee_rate = ray_div(ray_mul(ALPHA_1 - current_ratio, LAMBDA_1), ALPHA_1);
            let fee = ray_div(ray_mul(
                (total_liquidity - current_liquidity) * ray_mul(fee_rate, ray_ln2()),
                ray_log2(ray_div(total_liquidity - n_start, total_liquidity - withdraw_amount))
            ), ray_mul(ALPHA_1, expected_ratio)) - ray_div(
                (withdraw_amount - n_start) * ray_mul(fee_rate, ray() - ray_mul(ALPHA_1, expected_ratio)),
                ray_mul(ALPHA_1, expected_ratio)
            );
            fee
        }
    }
}
