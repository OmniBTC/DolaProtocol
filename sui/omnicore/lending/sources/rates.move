module lending::rates {

    use lending::math::{ray_mul, ray_div};
    use lending::storage::{Storage, get_dtoken_scaled_total_supply, get_borrow_rate_factors, get_treasury_factor, get_borrow_index};

    const RAY: u64 = 100000000;

    public fun calculate_utilization(storage: &mut Storage, dola_pool_id: u16, liquidity: u128): u64 {
        let scale_balance = get_dtoken_scaled_total_supply(storage, dola_pool_id);
        let cur_borrow_index = get_borrow_index(storage, dola_pool_id);
        let debt = scale_balance * (cur_borrow_index as u128) / (RAY as u128);
        ((debt * (RAY as u128) / (debt + liquidity)) as u64)
    }

    public fun calculate_borrow_rate(storage: &mut Storage, dola_pool_id: u16, liquidity: u128): u64 {
        let utilization = calculate_utilization(storage, dola_pool_id, liquidity);
        let (base_borrow_rate, borrow_rate_slope1, borrow_rate_slope2, optimal_utilization) = get_borrow_rate_factors(
            storage,
            dola_pool_id
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

    public fun calculate_liquidity_rate(
        storage: &mut Storage,
        dola_pool_id: u16,
        borrow_rate: u64,
        liquidity: u128
    ): u64 {
        let utilization = calculate_utilization(storage, dola_pool_id, liquidity);
        let treasury_factor = get_treasury_factor(storage, dola_pool_id);
        ray_mul(borrow_rate, ray_mul(utilization, RAY - treasury_factor))
    }
}
