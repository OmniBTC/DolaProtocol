module lending::rates {

    use lending::math::{ray_mul, ray_div};
    use lending::storage::{Storage, get_otoken_scaled_total_supply, get_dtoken_scaled_total_supply, get_borrow_rate_factors, get_treasury_factor};

    const RAY: u64 = 100000000;

    public fun calculate_utilization(storage: &mut Storage, token_name: vector<u8>): u64 {
        let liquidity = get_otoken_scaled_total_supply(storage, token_name);
        let debt = get_dtoken_scaled_total_supply(storage, token_name);
        ((debt * (RAY as u128) / liquidity) as u64)
    }

    public fun calculate_borrow_rate(storage: &mut Storage, token_name: vector<u8>): u64 {
        let utilization = calculate_utilization(storage, token_name);
        let (base_borrow_rate, borrow_rate_slope1, borrow_rate_slope2, optimal_utilization) = get_borrow_rate_factors(
            storage,
            token_name
        );
        if (utilization < optimal_utilization) {
            base_borrow_rate + ray_mul(utilization, borrow_rate_slope1)
        } else {
            base_borrow_rate + borrow_rate_slope1 + ray_mul(
                borrow_rate_slope2,
                ray_div(utilization - optimal_utilization, RAY - optimal_utilization)
            )
        }
    }

    public fun calculate_liquidity_rate(storage: &mut Storage, token_name: vector<u8>, borrow_rate: u64): u64 {
        let utilization = calculate_utilization(storage, token_name);
        let treasury_factor = get_treasury_factor(storage, token_name);
        ray_mul(borrow_rate, ray_mul(utilization, RAY - treasury_factor))
    }
}
