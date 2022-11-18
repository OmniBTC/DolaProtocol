module lending::logic {
    use lending::storage::{StorageCap, Storage, get_liquidity_index};
    use lending::scaled_balance;
    use lending::storage;

    const RAY: u64 = 100000000;

    const SECONDS_PER_YEAR: u64 = 31536000;

    public fun mint_otoken(
        cap: &StorageCap, // todo! Where manage this?
        storage: &mut Storage,
        user: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, token_name));
        storage::mint_otoken_scaled(
            cap,
            storage,
            token_name,
            user,
            scaled_amount
        );
    }

    public fun burn_otoken(
        cap: &StorageCap,
        storage: &mut Storage,
        user: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, token_name));
        storage::burn_otoken_scaled(
            cap,
            storage,
            token_name,
            user,
            scaled_amount
        );
    }

    public fun mint_dtoken(
        cap: &StorageCap,
        storage: &mut Storage,
        user: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, token_name));
        storage::mint_dtoken_scaled(
            cap,
            storage,
            token_name,
            user,
            scaled_amount
        );
    }

    public fun burn_dtoken(
        cap: &StorageCap,
        storage: &mut Storage,
        user: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
    ) {
        let scaled_amount = scaled_balance::mint_scaled(token_amount, get_liquidity_index(storage, token_name));
        storage::burn_dtoken_scaled(
            cap,
            storage,
            token_name,
            user,
            scaled_amount
        );
    }

    public fun update_state(
        cap: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
    ) {
        // todo! fix
        let current_timestamp = 0;

        let last_update_timestamp = storage::get_last_update_timestamp(storage, token_name);
        let dtoken_scaled_total_supply = storage::get_dtoken_scaled_total_supply(storage, token_name);
        let current_borrow_index = storage::get_borrow_index(storage, token_name);

        let treasury_factor = storage::get_treasury_factor(storage, token_name);

        let new_borrow_index = calculate_compounded_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_borrow_rate(storage, token_name)
        );

        let new_liquidity_index = calculate_linear_interest(
            current_timestamp,
            last_update_timestamp,
            storage::get_liquidity_rate(storage, token_name)
        );

        let mint_to_treasury = ((dtoken_scaled_total_supply *
            ((new_borrow_index - current_borrow_index) as u128) /
            (RAY as u128) * (treasury_factor as u128) / (RAY as u128)) as u64);
        storage::update_state(cap, storage, token_name, new_borrow_index, new_liquidity_index, mint_to_treasury);
    }

    public fun update_interest_rate(
        _: &StorageCap,
        _storage: &mut Storage,
        _token_name: vector<u8>,
    ) {
        // todo! fix
    }


    public fun ray_mul(a: u64, b: u64): u64 {
        ((a as u128) * (b as u128) / (RAY as u128) as u64)
    }

    public fun calculate_compounded_interest(
        current_timestamp: u64,
        last_update_timestamp: u64,
        rate: u64,
    ): u64 {
        let exp = current_timestamp - last_update_timestamp;

        if (exp == 0) {
            // todo! fix?
            return rate
        };

        let exp_minus_one: u64;
        let exp_minus_two: u64;
        let base_power_two: u64;
        let base_power_three: u64;
        exp_minus_one = exp - 1;

        if (exp > 2) {
            exp_minus_two = exp - 2;
        }else {
            exp_minus_two = 0;
        };

        base_power_two = ray_mul(rate, rate) / (SECONDS_PER_YEAR * SECONDS_PER_YEAR);

        base_power_three = ray_mul(base_power_two, rate) / SECONDS_PER_YEAR;

        let second_term = exp * exp_minus_one * base_power_two;
        second_term = second_term / 2;
        let third_term = exp * exp_minus_one * exp_minus_two * base_power_three;
        third_term = third_term / 6;

        RAY + (rate * exp) / SECONDS_PER_YEAR + second_term + third_term
    }

    public fun calculate_linear_interest(
        current_timestamp: u64,
        last_update_timestamp: u64,
        rate: u64,
    ): u64 {
        let result = rate * (current_timestamp - last_update_timestamp);
        result = result / SECONDS_PER_YEAR;

        RAY + result
    }
}
