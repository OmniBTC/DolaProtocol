module lending_core::scaled_balance {
    use ray_math::math;

    public fun balance_of(
        user_scaled_balance: u256,
        current_index: u256
    ): u256 {
        math::ray_mul(user_scaled_balance, current_index)
    }

    public fun mint_scaled(
        token_amount: u256,
        current_index: u256
    ): u256 {
        math::ray_div(token_amount, current_index)
    }

    public fun burn_scaled(
        token_amount: u256,
        current_index: u256
    ): u256 {
        math::ray_div(token_amount, current_index)
    }
}
