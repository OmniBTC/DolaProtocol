module lending::scaled_balance {
    use lending::math;

    const RAY: u64 = 100000000;

    public fun balance_of(
        user_scaled_balance: u64,
        current_index: u64
    ): u64 {
        math::ray_mul(user_scaled_balance, current_index)
    }

    public fun mint_scaled(
        token_amount: u64,
        current_index: u64
    ): u64 {
        math::ray_div(token_amount, current_index)
    }

    public fun burn_scaled(
        token_amount: u64,
        current_index: u64
    ): u64 {
        math::ray_div(token_amount, current_index)
    }
}
