module pool_manager::equilibrium_fee {

    use ray_math::math;

    public fun calculate_expected_ratio(total_weight: u256, weight: u256): u256 {
        if (total_weight == 0) {
            0
        }else {
            math::ray_div(weight, total_weight)
        }
    }

    public fun calculate_liquidity_percent(
        current_liquidity: u256,
        total_liquidity: u256,
        expected_ratio: u256
    ): u256 {
        math::ray_div(math::ray_div(current_liquidity, total_liquidity), expected_ratio)
    }

    /// Reference for details:
    /// https://github.com/OmniBTC/DOLA-Protocol/tree/main/en#213-single-coin-pool-manager-poolmanage
    public fun calculate_equilibrium_fee(
        total_liquidity: u256,
        current_liquidity: u256,
        withdraw_amount: u256,
        expected_ratio: u256,
        alpha_1: u256,
        lambda_1: u256
    ): u256 {
        if (expected_ratio == 0) {
            return 0
        };

        let after_liquidity_ratio = if (total_liquidity > withdraw_amount)
            {
                calculate_liquidity_percent(
                    current_liquidity - withdraw_amount,
                    total_liquidity - withdraw_amount,
                    expected_ratio
                )
            } else { 0 };

        let n_start = if (current_liquidity > math::ray_mul(math::ray_mul(total_liquidity, expected_ratio), alpha_1))
            {
                math::ray_div(
                    current_liquidity - math::ray_mul(math::ray_mul(total_liquidity, alpha_1), expected_ratio),
                    math::ray() - math::ray_mul(alpha_1, expected_ratio)
                )
            } else { 0 };

        if (after_liquidity_ratio == 0) {
            withdraw_amount
        } else if (after_liquidity_ratio > alpha_1) {
            0
        } else {
            let fee = math::ray_div(math::ray_mul(
                (total_liquidity - current_liquidity) * math::ray_mul(lambda_1, math::ray_ln2()),
                math::ray_log2(math::ray_div(total_liquidity - n_start, total_liquidity - withdraw_amount))
            ), math::ray_mul(alpha_1, expected_ratio)) - math::ray_div(
                (withdraw_amount - n_start) * math::ray_mul(
                    lambda_1,
                    math::ray() - math::ray_mul(alpha_1, expected_ratio)
                ),
                math::ray_mul(alpha_1, expected_ratio)
            );
            fee
        }
    }

    public fun calculate_equilibrium_reward(
        total_liquidity: u256,
        current_liquidity: u256,
        deposit_amount: u256,
        expected_ratio: u256,
        total_equilibrium_reward: u256,
        alpha_1: u256
    ): u256 {
        if (deposit_amount == 0 || expected_ratio == 0 || total_liquidity == 0) {
            return 0
        };

        let before_liquidity_ratio = calculate_liquidity_percent(
            current_liquidity,
            total_liquidity,
            expected_ratio
        );

        let after_liquidity_ratio = calculate_liquidity_percent(
            current_liquidity + deposit_amount,
            total_liquidity + deposit_amount,
            expected_ratio
        );

        if (before_liquidity_ratio >= alpha_1) {
            0
        } else {
            if (after_liquidity_ratio >= alpha_1) {
                total_equilibrium_reward
            } else {
                let reward_ratio = math::ray_div(
                    after_liquidity_ratio - before_liquidity_ratio,
                    alpha_1 - before_liquidity_ratio
                );
                math::ray_mul(total_equilibrium_reward, reward_ratio)
            }
        }
    }


    #[test]
    fun test_calculate_equilibrium_fee() {
        let alpha_1 = 600000000000000000000000000;
        let lambda_1 = 5000000000000000000000000;

        // before liquidity ratio > 60%
        // after liquidity ratio > 60%
        let total_liquidity = 10000;
        let current_liquidity = 4000;
        let withdraw_amount = 500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let fee0 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        assert!(fee0 == 0, 0);

        // before liquidity ratio > 60%
        // after liquidity ratio == 55%
        // fee ratio == 5%
        let total_liquidity = 10000;
        let current_liquidity = 4000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 550000000000000000000000000;
        // wa = (c-e*r*t)/(1-e*r)
        let withdraw_amount = math::ray_div(
            current_liquidity - math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio),
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let fee1 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        assert!(fee1 > 0, 1);

        // before liquidity ratio == 50%
        // after liquidity ratio == 40%
        // fee ratio == 10%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 400000000000000000000000000;
        // wa = (c-e*r*t)/(1-e*r)
        let withdraw_amount = math::ray_div(
            current_liquidity - math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio),
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let fee2 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        assert!(fee2 > 0, 3);

        // before liquidity ratio == 40%
        // withdraw_amount2 == withdraw_amount3
        // fee2 == fee3
        let total_liquidity = total_liquidity - withdraw_amount;
        let current_liquidity = current_liquidity - withdraw_amount;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let withdraw_amount = withdraw_amount;
        let fee3 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        assert!(fee3 > 0, 3);

        // before liquidity ratio == 50%
        // after liquidity ratio == 40%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let withdraw_amount = 2 * withdraw_amount;
        let fee4 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        assert!(fee4 > 0, 4);
        assert!(fee4 / 100000 == (fee3 + fee2) / 100000, 5);

        // before liquidity ratio == 50%
        // after liquidity ratio == 0%
        // fee ratio == 50%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let withdraw_amount = current_liquidity;
        let fee5 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        assert!(fee5 == withdraw_amount, 6);
    }

    #[test]
    fun test_calculate_equilibrium_reward() {
        let alpha_1 = 600000000000000000000000000;
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
            total_equilibrium_reward,
            alpha_1
        );
        assert!(reward1 == 0, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 55%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 550000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = math::ray_div(
            math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio) - current_liquidity,
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let total_equilibrium_reward = 100;
        let reward2 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward,
            alpha_1
        );
        assert!(reward2 == total_equilibrium_reward / 2, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 60%
        let total_liquidity = 10000;
        let current_liquidity = 2500;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_ratio = 600000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = math::ray_div(
            math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_ratio) - current_liquidity,
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_ratio)
        );
        let total_equilibrium_reward = 100;
        let reward3 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward,
            alpha_1
        );
        assert!(reward3 == total_equilibrium_reward, 0);
    }
}
