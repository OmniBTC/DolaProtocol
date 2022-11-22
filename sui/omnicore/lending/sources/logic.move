module lending::logic {
    use std::vector;

    use omnipool::pool::Pool;

    use lending::math::{calculate_compounded_interest, calculate_linear_interest};
    use lending::rates;
    use lending::scaled_balance::{Self, balance_of};
    use lending::storage::{Self, StorageCap, Storage, get_liquidity_index, get_user_collaterals, get_user_scaled_otoken, get_user_loans, get_user_scaled_dtoken, add_user_collateral, add_user_loan, get_otoken_scaled_total_supply, get_borrow_index, get_dtoken_scaled_total_supply, get_app_id, remove_user_collateral, get_app_cap, remove_user_loan};
    use oracle::oracle::{get_token_price, PriceOracle};
    use pool_manager::pool_manager::{Self, PoolManagerInfo};
    use serde::serde::deserialize_u64;
    use sui::bcs;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::tx_context::{epoch, TxContext};
    use wormhole::state::State as WormholeState;
    use wormhole_bridge::bridge_core::{Self, CoreState};

    const RAY: u64 = 100000000;

    const ECOLLATERAL_AS_LOAN: u64 = 0;

    const ENOT_HEALTH: u64 = 1;

    const EIS_HEALTH: u64 = 2;

    const ENOT_COLLATERAL: u64 = 3;

    const ENOT_LOAN: u64 = 4;

    const ENOT_ENOUGH_OTOKEN: u64 = 5;

    const ENOT_ENOUGH_LIQUIDITY: u64 = 6;

    public fun liquidate(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: vector<u8>,
        user_address: vector<u8>,
        collateral: vector<u8>,
        loan_token: vector<u8>,
        ctx: &mut TxContext
    ) {
        update_state(cap, storage, loan_token, ctx);
        update_state(cap, storage, collateral, ctx);
        assert!(is_collateral(storage, user_address, collateral), ENOT_COLLATERAL);
        assert!(is_loan(storage, user_address, loan_token), ENOT_LOAN);
        assert!(!check_health_factor(storage, oracle, user_address), EIS_HEALTH);
        let liquidated_debt = user_loan_balance(storage, user_address, loan_token) / 2;
        let liquidated_debt_val = user_loan_value(storage, oracle, user_address, loan_token) / 2;
        let (collateral_price, decimal) = get_token_price(oracle, collateral);
        // todo: fix calculation
        let collateral_amount = liquidated_debt_val * decimal / collateral_price;
        burn_dtoken(cap, storage, user_address, loan_token, liquidated_debt);
        burn_otoken(cap, storage, user_address, collateral, collateral_amount);
        mint_otoken(cap, storage, liquidator, collateral, collateral_amount);
        update_interest_rate(cap, pool_manager_info, storage, collateral);
        update_interest_rate(cap, pool_manager_info, storage, loan_token);
    }

    public entry fun supply(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        vaa: vector<u8>,
        cap: &StorageCap,
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let (token_name, user, amount, _app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        inner_supply(cap, pool_manager_info, storage, bcs::to_bytes(&user), token_name, amount, ctx);
    }

    fun inner_supply(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
        ctx: &mut TxContext
    ) {
        update_state(cap, storage, token_name, ctx);
        update_interest_rate(cap, pool_manager_info, storage, token_name);
        mint_otoken(cap, storage, user_address, token_name, token_amount);
        assert!(!is_loan(storage, user_address, token_name), ENOT_LOAN);
        if (!is_collateral(storage, user_address, token_name)) {
            add_user_collateral(cap, storage, user_address, token_name);
        }
    }

    public fun decode_app_payload(app_payload: vector<u8>): u64 {
        deserialize_u64(&app_payload)
    }

    public entry fun withdraw<CoinType>(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        chainid: u64,
        wormhole_message_fee: Coin<SUI>,
        cap: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        pool_manager_info: &mut PoolManagerInfo,
        ctx: &mut TxContext
    ) {
        let (token_name, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let token_amount = decode_app_payload(app_payload);
        inner_withdraw(cap, storage, oracle, pool_manager_info, bcs::to_bytes(&user), token_name, token_amount, ctx);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            pool,
            chainid,
            user,
            token_amount,
            token_name,
            wormhole_message_fee
        );
    }

    fun inner_withdraw(
        cap: &StorageCap,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        pool_manager_info: &PoolManagerInfo,
        user_address: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
        ctx: &mut TxContext
    ) {
        update_state(cap, storage, token_name, ctx);
        // check otoken amount
        let otoken_amount = user_collateral_balance(storage, user_address, token_name);
        assert!(token_amount <= otoken_amount, ENOT_ENOUGH_OTOKEN);
        update_interest_rate(cap, pool_manager_info, storage, token_name);

        burn_otoken(cap, storage, user_address, token_name, token_amount);

        assert!(check_health_factor(storage, oracle, user_address), ENOT_HEALTH);
        if (token_amount == otoken_amount) {
            remove_user_collateral(cap, storage, user_address, token_name);
        }
    }

    public entry fun borrow<CoinType>(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        pool: &mut Pool<CoinType>,
        vaa: vector<u8>,
        chainid: u64,
        wormhole_message_fee: Coin<SUI>,
        cap: &StorageCap,
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        ctx: &mut TxContext
    ) {
        let (token_name, user, app_payload) = bridge_core::receive_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            ctx
        );
        let user_address = bcs::to_bytes(&user);
        let token_amount = decode_app_payload(app_payload);
        inner_borrow(cap, pool_manager_info, storage, oracle, user_address, token_name, token_amount, ctx);
        bridge_core::send_withdraw(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            pool_manager_info,
            pool,
            chainid,
            user,
            token_amount,
            token_name,
            wormhole_message_fee
        );
    }

    fun inner_borrow(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
        ctx: &mut TxContext
    ) {
        update_state(cap, storage, token_name, ctx);

        assert!(!is_collateral(storage, user_address, token_name), ECOLLATERAL_AS_LOAN);
        if (!is_loan(storage, user_address, token_name)) {
            add_user_loan(cap, storage, user_address, token_name);
        };
        mint_dtoken(cap, storage, user_address, token_name, token_amount);

        let liquidity = pool_manager::get_app_liquidity(pool_manager_info, token_name, get_app_id(storage));
        assert!((token_amount as u128) < liquidity, ENOT_ENOUGH_LIQUIDITY);
        assert!(check_health_factor(storage, oracle, user_address), ENOT_HEALTH);
        update_interest_rate(cap, pool_manager_info, storage, token_name);
    }

    public entry fun repay(
        wormhole_state: &mut WormholeState,
        core_state: &mut CoreState,
        vaa: vector<u8>,
        cap: &StorageCap,
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        ctx: &mut TxContext
    ) {
        let (token_name, user, amount, _app_payload) = bridge_core::receive_deposit(
            wormhole_state,
            core_state,
            get_app_cap(cap, storage),
            vaa,
            pool_manager_info,
            ctx
        );
        inner_repay(cap, pool_manager_info, storage, bcs::to_bytes(&user), token_name, amount, ctx);
    }

    fun inner_repay(
        cap: &StorageCap,
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>,
        token_amount: u64,
        ctx: &mut TxContext
    ) {
        update_state(cap, storage, token_name, ctx);
        let debt = user_loan_balance(storage, user_address, token_name);
        let repay_debt = if (debt > token_amount) { token_amount } else { debt };
        burn_dtoken(cap, storage, user_address, token_name, repay_debt);
        update_interest_rate(cap, pool_manager_info, storage, token_name);
        if (token_amount == repay_debt) {
            remove_user_loan(cap, storage, user_address, token_name);
        }
    }

    public fun check_health_factor(storage: &mut Storage, oracle: &mut PriceOracle, user_address: vector<u8>): bool {
        let collateral_value = user_total_collateral_value(storage, oracle, user_address);
        let loan_value = user_total_loan_value(storage, oracle, user_address);
        collateral_value >= loan_value
    }

    public fun is_collateral(storage: &mut Storage, user_address: vector<u8>, token_name: vector<u8>): bool {
        let collaterals = get_user_collaterals(storage, user_address);
        vector::contains(&collaterals, &token_name)
    }

    public fun is_loan(storage: &mut Storage, user_address: vector<u8>, token_name: vector<u8>): bool {
        let loans = get_user_loans(storage, user_address);
        vector::contains(&loans, &token_name)
    }

    public fun user_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>
    ): u64 {
        let balance = user_collateral_balance(storage, user_address, token_name);
        let (price, decimal) = get_token_price(oracle, token_name);
        (((balance as u128) * (price as u128) / (decimal as u128)) as u64)
    }

    public fun user_collateral_balance(
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ): u64 {
        let scaled_balance = get_user_scaled_otoken(storage, user_address, token_name);
        let current_index = get_liquidity_index(storage, token_name);
        balance_of(scaled_balance, current_index)
    }

    public fun user_loan_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>
    ): u64 {
        let balance = user_loan_balance(storage, user_address, token_name);
        let (price, decimal) = get_token_price(oracle, token_name);
        (((balance as u128) * (price as u128) / (decimal as u128)) as u64)
    }

    public fun user_loan_balance(
        storage: &mut Storage,
        user_address: vector<u8>,
        token_name: vector<u8>
    ): u64 {
        let scaled_balance = get_user_scaled_dtoken(storage, user_address, token_name);
        let current_index = get_liquidity_index(storage, token_name);
        balance_of(scaled_balance, current_index)
    }


    public fun user_total_collateral_value(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>
    ): u64 {
        let collaterals = get_user_collaterals(storage, user_address);
        let length = vector::length(&collaterals);
        let value = 0;
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            // todo: fix token decimal
            let collateral_value = user_collateral_value(storage, oracle, user_address, *collateral);
            value = value + collateral_value;
            i = i + 1;
        };
        value
    }

    public fun user_total_loan_value(storage: &mut Storage, oracle: &mut PriceOracle, user_address: vector<u8>): u64 {
        let loans = get_user_collaterals(storage, user_address);
        let length = vector::length(&loans);
        let value = 0;
        let i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            // todo: fix token decimal
            let loan_value = user_loan_value(storage, oracle, user_address, *loan);
            value = value + loan_value;
            i = i + 1;
        };
        value
    }

    public fun total_otoken_supply(storage: &mut Storage, token_name: vector<u8>): u128 {
        let scaled_total_otoken_supply = get_otoken_scaled_total_supply(storage, token_name);
        let current_index = get_liquidity_index(storage, token_name);
        scaled_total_otoken_supply * (current_index as u128) / (RAY as u128)
    }

    public fun total_dtoken_supply(storage: &mut Storage, token_name: vector<u8>): u128 {
        let scaled_total_dtoken_supply = get_dtoken_scaled_total_supply(storage, token_name);
        let current_index = get_borrow_index(storage, token_name);
        scaled_total_dtoken_supply * (current_index as u128) / (RAY as u128)
    }

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
        pool_manager_info: &PoolManagerInfo,
        storage: &mut Storage,
        token_name: vector<u8>,
    ) {
        let liquidity = pool_manager::get_app_liquidity(pool_manager_info, token_name, get_app_id(storage));
        let borrow_rate = rates::calculate_borrow_rate(storage, token_name, liquidity);
        let liquidity_rate = rates::calculate_liquidity_rate(storage, token_name, borrow_rate, liquidity);
        storage::update_interest_rate(cap, storage, token_name, borrow_rate, liquidity_rate);
    }
}
