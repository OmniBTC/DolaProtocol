module lending::scaled_balance {
    const RAY: u64 = 100000000;

    public fun total_supply(
        scaled_total_supply: u128,
        current_index: u64,
    ): u128 {
        scaled_total_supply * (current_index as u128)
    }

    public fun balance_of(
        user_scaled_balance: u64,
        current_index: u64
    ): u64 {
        ((((user_scaled_balance as u128) * (current_index as u128) + (RAY / 2 as u128)) / (RAY as u128)) as u64)
    }

    public fun mint_scaled(
        token_amount: u64,
        current_index: u64
    ): u64 {
        ((token_amount as u128) * (RAY as u128) / (current_index as u128) as u64)
    }

    public fun burn_scaled(
        token_amount: u64,
        current_index: u64
    ): u64 {
        (((token_amount as u128) * (RAY as u128) + (current_index / 2 as u128)) / (current_index as u128) as u64)
    }
}
