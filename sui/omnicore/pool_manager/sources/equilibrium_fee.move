module pool_manager::equilibrium_fee {

    use ray_math::math::{ray_div, ray, ray_mul, ray_ln2, ray_log2};

    /// Equilibrium fees are charged when liquidity is less than 60% of the target liquidity.
    const ALPHA_1: u256 = 600000000000000000000000000;

    /// Fee ratio 0.5%
    const LAMBDA_1: u256 = 5000000000000000000000000;

    public fun calculate_expected_ratio(total_weight: u16, weight: u8): u256 {
        ray_div((weight as u256), (total_weight as u256))
    }

    public fun calculate_equilibrium_reward(
        total_liquidity: u256,
        current_liquidity: u256,
        deposit_amount: u256,
        expected_ratio: u256,
        total_equilibrium_reward: u256
    ): u256 {
        let before_liquidity_ratio = if (total_liquidity > 0) {
            ray_div(
                ray_div(current_liquidity, total_liquidity),
                expected_ratio
            )
        } else { 0 };
        let after_liquidity_ratio = ray_div(
            ray_div(current_liquidity + deposit_amount, total_liquidity + deposit_amount),
            expected_ratio
        );

        if (before_liquidity_ratio >= ALPHA_1) {
            0
        } else {
            if (after_liquidity_ratio >= ALPHA_1) {
                total_equilibrium_reward
            } else {
                let reward_ratio = ray_div(
                    after_liquidity_ratio - before_liquidity_ratio,
                    ALPHA_1 - before_liquidity_ratio
                );
                ray_mul(total_equilibrium_reward, reward_ratio)
            }
        }
    }

    public fun calculate_equilibrium_fee(
        total_liquidity: u256,
        current_liquidity: u256,
        withdraw_amount: u256,
        expected_ratio: u256
    ): u256 {
        let after_liquidity_ratio = if (total_liquidity > withdraw_amount) {
            ray_div(
                ray_div(current_liquidity - withdraw_amount, total_liquidity - withdraw_amount),
                expected_ratio
            )
        } else { 0 };

        let n_start = if (current_liquidity > ray_mul(ray_mul(total_liquidity, expected_ratio), ALPHA_1)) {
            ray_div(
                current_liquidity - ray_mul(ray_mul(total_liquidity, ALPHA_1), expected_ratio),
                ray() - ray_mul(ALPHA_1, expected_ratio)
            )
        } else { 0 };

        if (after_liquidity_ratio == 0) {
            withdraw_amount
        } else if (after_liquidity_ratio > ALPHA_1) {
            0
        } else {
            let fee = ray_div(ray_mul(
                (total_liquidity - current_liquidity) * ray_mul(LAMBDA_1, ray_ln2()),
                ray_log2(ray_div(total_liquidity - n_start, total_liquidity - withdraw_amount))
            ), ray_mul(ALPHA_1, expected_ratio)) - ray_div(
                (withdraw_amount - n_start) * ray_mul(LAMBDA_1, ray() - ray_mul(ALPHA_1, expected_ratio)),
                ray_mul(ALPHA_1, expected_ratio)
            );
            fee
        }
    }

    #[test]
    fun test_calculate_equilibrium_fee() {
        // before liquidity ratio > 60%
        // after liquidity ratio > 60%
        let total_liquidity = 10000;
        let current_liquidity = 4000;
        let withdraw_amount = 500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let fee0 = calculate_equilibrium_fee(total_liquidity, current_liquidity, withdraw_amount, expect_ratio);
        assert!(fee0 == 0, 0);

        // before liquidity ratio > 60%
        // after liquidity ratio == 55%
        // fee ratio == 5%
        let total_liquidity = 10000;
        let current_liquidity = 4000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 550000000000000000000000000;
        // wa = (c-e*r*t)/(1-e*r)
        let withdraw_amount = ray_div(
            current_liquidity - ray_mul(ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio),
            ray() - ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let fee1 = calculate_equilibrium_fee(total_liquidity, current_liquidity, withdraw_amount, expect_ratio);
        assert!(fee1 > 0, 1);

        // before liquidity ratio == 50%
        // after liquidity ratio == 40%
        // fee ratio == 10%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 400000000000000000000000000;
        // wa = (c-e*r*t)/(1-e*r)
        let withdraw_amount = ray_div(
            current_liquidity - ray_mul(ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio),
            ray() - ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let fee2 = calculate_equilibrium_fee(total_liquidity, current_liquidity, withdraw_amount, expect_ratio);
        assert!(fee2 > 0, 3);

        // before liquidity ratio == 40%
        // withdraw_amount2 == withdraw_amount3
        // fee2 == fee3
        let total_liquidity = total_liquidity - withdraw_amount;
        let current_liquidity = current_liquidity - withdraw_amount;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let withdraw_amount = withdraw_amount;
        let fee3 = calculate_equilibrium_fee(total_liquidity, current_liquidity, withdraw_amount, expect_ratio);
        assert!(fee3 > 0, 3);

        // before liquidity ratio == 50%
        // after liquidity ratio == 40%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let withdraw_amount = 2 * withdraw_amount;
        let fee4 = calculate_equilibrium_fee(total_liquidity, current_liquidity, withdraw_amount, expect_ratio);
        assert!(fee4 > 0, 4);
        assert!(fee4 / 100000 == (fee3 + fee2) / 100000, 5);

        // before liquidity ratio == 50%
        // after liquidity ratio == 0%
        // fee ratio == 50%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let withdraw_amount = current_liquidity;
        let fee5 = calculate_equilibrium_fee(total_liquidity, current_liquidity, withdraw_amount, expect_ratio);
        assert!(fee5 == withdraw_amount, 6);
    }

    #[test]
    fun test_calculate_equilibrium_reward() {
        // before liquidity ratio > 60%
        let total_liquidity = 10000;
        let current_liquidity = 4000;
        let deposit_amount = 500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let total_equilibrium_reward = 0;
        let reward1 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward
        );
        assert!(reward1 == 0, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 55%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 550000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = ray_div(
            ray_mul(ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio) - current_liquidity,
            ray() - ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let total_equilibrium_reward = 100;
        let reward2 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward
        );
        assert!(reward2 == total_equilibrium_reward / 2, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 60%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 600000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = ray_div(
            ray_mul(ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio) - current_liquidity,
            ray() - ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let total_equilibrium_reward = 100;
        let reward3 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward
        );
        assert!(reward3 == total_equilibrium_reward, 0);
    }
}
