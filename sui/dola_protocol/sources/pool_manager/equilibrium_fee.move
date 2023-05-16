// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

module dola_protocol::equilibrium_fee {

    use dola_protocol::ray_math as math;

    /// === Helper Functions ===

    /// Calculate expected ratio according to weight
    public fun calculate_expected_ratio(total_weight: u256, weight: u256): u256 {
        if (total_weight == 0) {
            0
        }else {
            math::ray_div(weight, total_weight)
        }
    }

    /// Calculate liquidity percentage according to current liquidity and expected ratio
    public fun calculate_liquidity_percent(
        current_liquidity: u256,
        total_liquidity: u256,
        expected_ratio: u256
    ): u256 {
        if (total_liquidity == 0) {
            0
        }else {
            let percent = math::ray_div(math::ray_div(current_liquidity, total_liquidity), expected_ratio);
            math::min(percent, math::ray())
        }
    }

    /// Calculate equilibrium fee based on the extent to which the current liquidity ratio
    /// differs from the expected ratio
    /// Reference for details:
    ///     https://github.com/OmniBTC/DOLA-Protocol/tree/main/en#213-single-coin-pool-manager-poolmanage
    public fun calculate_equilibrium_fee(
        total_liquidity: u256,
        current_liquidity: u256,
        withdraw_amount: u256,
        expected_ratio: u256,
        alpha_1: u256,
        lambda_1: u256
    ): u256 {
        if (expected_ratio == 0 || current_liquidity == total_liquidity) {
            return 0
        };

        let after_liquidity_percent = calculate_liquidity_percent(
            current_liquidity - withdraw_amount,
            total_liquidity - withdraw_amount,
            expected_ratio
        );

        if (after_liquidity_percent > alpha_1) {
            return 0
        };

        let before_liquidity_percent = calculate_liquidity_percent(
            current_liquidity,
            total_liquidity,
            expected_ratio
        );

        // Compute n_start
        let n_start = if (before_liquidity_percent > alpha_1)
            {
                math::ray_div(
                    current_liquidity - math::ray_mul(math::ray_mul(total_liquidity, alpha_1), expected_ratio),
                    math::ray() - math::ray_mul(alpha_1, expected_ratio)
                )
            } else { 0 };

        // Calculus for fee
        // The amount decimal is 8, other decimal is 27
        let first_item =
            (withdraw_amount - n_start) * math::ray_mul(
                lambda_1,
                math::ray() - math::ray_mul(alpha_1, expected_ratio)
            ) / math::ray_mul(alpha_1, expected_ratio)
        ;

        let second_item =
            math::ray_mul(
                (total_liquidity - current_liquidity) * math::ray_mul(lambda_1, math::ray_ln2()),
                math::ray_log2(math::ray_div(total_liquidity - n_start, total_liquidity - withdraw_amount))
            ) / math::ray_mul(alpha_1, expected_ratio);

        second_item - first_item
    }

    /// Calculate equilibrium reward based on the extent to which the current liquidity ratio
    /// differs from the expected ratio and deposit amount differs from target amount
    public fun calculate_equilibrium_reward(
        total_liquidity: u256,
        current_liquidity: u256,
        deposit_amount: u256,
        expected_ratio: u256,
        total_equilibrium_reward: u256,
        lambda_1: u256
    ): u256 {
        if (expected_ratio == 0 || total_equilibrium_reward == 0) {
            return 0
        };

        // Calculate the reward percentage based on the value of the difference between before and after recharge
        // and the expected ratio
        let before_liquidity_percent = calculate_liquidity_percent(
            current_liquidity,
            total_liquidity,
            expected_ratio
        );
        let after_liquidity_percent = calculate_liquidity_percent(
            current_liquidity + deposit_amount,
            total_liquidity + deposit_amount,
            expected_ratio
        );
        let reward_ratio_1 = after_liquidity_percent - before_liquidity_percent;

        // Calculate the ratio based on the target number
        let target_amount = 2 * math::ray_div(total_equilibrium_reward, lambda_1);
        let reward_ratio_2 = math::min(
            math::ray_div(deposit_amount, target_amount),
            math::ray());

        // Choose the smaller of the two values
        let reward_ratio = math::min(reward_ratio_1, reward_ratio_2);
        math::ray_mul(total_equilibrium_reward, reward_ratio)
    }


    #[test]
    fun test_calculate_equilibrium_fee() {
        let alpha_1 = 600000000000000000000000000;
        let lambda_1 = 5000000000000000000000000;

        // before liquidity ratio > 60%
        // after liquidity ratio > 60%
        let total_liquidity = 1000000000000;
        let current_liquidity = 400000000000;
        let withdraw_amount = 50000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_percent = calculate_liquidity_percent(
            current_liquidity - withdraw_amount,
            total_liquidity - withdraw_amount,
            expect_ratio
        );
        // after_liquidity_percent approximate: 0.7
        assert!(after_liquidity_percent == 736842105263157894736842106, 0);
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
        let total_liquidity = 1000000000000;
        let current_liquidity = 400000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_percent = 550000000000000000000000000;
        // wa = (c-e*r*t)/(1-e*r)
        let withdraw_amount = math::ray_div(
            current_liquidity - math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_percent),
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_percent)
        );
        assert!(withdraw_amount == 172413793103, 0);
        let fee1 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        // 0.06
        assert!(fee1 == 6085612, 0);

        // before liquidity ratio == 50%
        // after liquidity ratio == 40%
        // fee ratio == 10%
        let total_liquidity = 1000000000000;
        let current_liquidity = 250000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_percent = 400000000000000000000000000;
        // wa = (c-e*r*t)/(1-e*r)
        let withdraw_amount = math::ray_div(
            current_liquidity - math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_percent),
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_percent)
        );

        assert!(withdraw_amount == 62500000000, 0);
        let fee2 = calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            expect_ratio,
            alpha_1,
            lambda_1
        );
        // 0.77
        assert!(fee2 == 77564848, 3);

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
        // 1.33
        assert!(fee3 == 133244227, 3);

        // before liquidity ratio == 50%
        // after liquidity ratio == 40%
        let total_liquidity = 1000000000000;
        let current_liquidity = 250000000000;
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
        // 2.1
        assert!(fee4 == 210809074, 4);
        assert!(fee4 / 100000 == (fee3 + fee2) / 100000, 5);

        // before liquidity ratio == 50%
        // after liquidity ratio == 0%
        // fee ratio == 50%
        let total_liquidity = 1000000000000;
        let current_liquidity = 250000000000;
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
        assert!(fee5 == 679359239, 6);
    }

    #[test]
    fun test_calculate_equilibrium_reward() {
        let lambda_1 = 5000000000000000000000000;
        // before liquidity ratio > 60%
        let total_liquidity = 1000000000000;
        let current_liquidity = 400000000000;
        let deposit_amount = 50000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let total_equilibrium_reward = 0;
        let reward1 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward,
            lambda_1
        );
        assert!(reward1 == 0, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 55%
        let total_liquidity = 1000000000000;
        let current_liquidity = 250000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_percent = 550000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = math::ray_div(
            math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_percent) - current_liquidity,
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_percent)
        );
        assert!(deposit_amount == 34482758621, 0);
        let total_equilibrium_reward = 10000000000;
        let reward2 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward,
            lambda_1
        );
        // 0.8
        assert!(reward2 == 86206897, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 60%
        let total_liquidity = 1000000000000;
        let current_liquidity = 250000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_percent = 600000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = math::ray_div(
            math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_percent) - current_liquidity,
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_percent)
        );
        assert!(deposit_amount == 71428571429, 0);
        let total_equilibrium_reward = 10000000000;
        let reward3 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward,
            lambda_1
        );
        // 1.7
        assert!(reward3 == 178571429, 0);

        // before liquidity ratio == 50%
        // after liqudity ratio == 60%
        let total_liquidity = 10000000000000;
        let current_liquidity = 2500000000000;
        let expect_ratio = calculate_expected_ratio(2, 1);
        let after_liquidity_percent = 600000000000000000000000000;
        // da = (t*e*r - c)/(1-e*r)
        let deposit_amount = math::ray_div(
            math::ray_mul(math::ray_mul(total_liquidity, expect_ratio), after_liquidity_percent) - current_liquidity,
            math::ray() - math::ray_mul(expect_ratio, after_liquidity_percent)
        );
        assert!(deposit_amount == 714285714286, 0);
        let total_equilibrium_reward = 10000000000;
        let reward4 = calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            expect_ratio,
            total_equilibrium_reward,
            lambda_1
        );
        // 10
        assert!(reward4 == 1000000000, 0);
    }
}
