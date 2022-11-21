module lending::logic {
    use lending::math::{calculate_compounded_interest, calculate_linear_interest};
    use lending::rates;
    use lending::scaled_balance;
    use lending::storage::{Self, StorageCap, Storage, get_liquidity_index};
    use sui::tx_context::{epoch, TxContext};

    const RAY: u64 = 100000000;

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
        ctx: &mut TxContext
    ) {
        // todo: use timestamp after sui implementation
        let current_timestamp = epoch(ctx);

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
        cap: &StorageCap,
        storage: &mut Storage,
        token_name: vector<u8>,
    ) {
        let borrow_rate = rates::calculate_borrow_rate(storage, token_name);
        let liquidity_rate = rates::calculate_liquidity_rate(storage, token_name, borrow_rate);
        storage::update_interest_rate(cap, storage, token_name, borrow_rate, liquidity_rate);
    }
}
