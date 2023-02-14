module lending_core::scaled_balance {
    use lending_core::math;

    public fun balance_of(
        user_scaled_balance: u64,
        current_index: u256
    ): u64 {
        (math::ray_mul((user_scaled_balance as u256), current_index) as u64)
    }

    public fun mint_scaled(
        token_amount: u64,
        current_index: u256
    ): u64 {
        (math::ray_div((token_amount as u256), current_index) as u64)
    }

    public fun burn_scaled(
        token_amount: u64,
        current_index: u256
    ): u64 {
        (math::ray_div((token_amount as u256), current_index) as u64)
    }
}
