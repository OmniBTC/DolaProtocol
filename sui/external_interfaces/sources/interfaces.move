// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Unified external call interface to get data
/// by simulating calls to trigger events.
module external_interfaces::interfaces {
    use std::ascii::into_bytes;
    use std::option::Self;
    use std::vector;

    use sui::clock::{Self, Clock};
    use sui::event::emit;

    use dola_protocol::dola_address::{Self, DolaAddress};
    use dola_protocol::equilibrium_fee;
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage::{Self as storage, Storage};
    use dola_protocol::lending_logic as logic;
    use dola_protocol::oracle::{Self, PriceOracle};
    use dola_protocol::pool_codec;
    use dola_protocol::pool_manager::{Self, PoolManagerInfo};
    use dola_protocol::rates;
    use dola_protocol::ray_math;
    use dola_protocol::user_manager::{Self, UserManagerInfo};
    use wormhole::state::State;
    use wormhole::vaa;

    const HOUR: u64 = 60 * 60;

    const MINUATE: u64 = 60;

    const U256_MAX: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    const TARGET_HF: u256 = 1050000000000000000000000000;

    struct TokenLiquidityInfo has copy, drop {
        dola_pool_id: u16,
        token_liquidity: u256,
    }

    struct AppLiquidityInfo has copy, drop {
        app_id: u16,
        dola_pool_id: u16,
        token_liquidity: u256,
    }

    struct PoolLiquidityInfo has copy, drop {
        pool_address: DolaAddress,
        pool_liquidity: u256,
        pool_equilibrium_fee: u256,
        pool_weight: u256
    }

    struct LiquidityEquilibriumReward has copy, drop {
        reward: u256
    }

    struct LiquidityEquilibriumFee has copy, drop {
        fee: u256
    }

    struct AllPoolLiquidityInfo has copy, drop {
        pool_infos: vector<PoolLiquidityInfo>,
    }

    struct LendingReserveInfo has copy, drop {
        dola_pool_id: u16,
        pools: vector<PoolLiquidityInfo>,
        total_pool_weight: u256,
        collateral_coefficient: u256,
        borrow_coefficient: u256,
        borrow_apy: u256,
        supply_apy: u256,
        reserve: u256,
        supply: u256,
        debt: u256,
        current_isolate_debt: u256,
        isolate_debt_ceiling: u256,
        is_isolate_asset: bool,
        borrowable_in_isolation: bool,
        utilization_rate: u256
    }

    struct AllReserveInfo has copy, drop {
        reserve_infos: vector<LendingReserveInfo>
    }

    struct UserLendingInfo has copy, drop {
        health_factor: u256,
        profit_state: bool,
        net_apy: u256,
        total_supply_apy: u256,
        total_borrow_apy: u256,
        liquid_asset_infos: vector<UserLiquidAssetInfo>,
        total_liquid_value: u256,
        collateral_infos: vector<UserCollateralInfo>,
        total_collateral_value: u256,
        debt_infos: vector<UserDebtInfo>,
        total_debt_value: u256,
        isolation_mode: bool
    }

    struct UserLiquidAssetInfo has copy, drop {
        dola_pool_id: u16,
        borrow_apy: u256,
        supply_apy: u256,
        liquid_amount: u256,
        liquid_value: u256
    }

    struct UserCollateralInfo has copy, drop {
        dola_pool_id: u16,
        borrow_apy: u256,
        supply_apy: u256,
        collateral_amount: u256,
        collateral_value: u256
    }

    struct UserDebtInfo has copy, drop {
        dola_pool_id: u16,
        borrow_apy: u256,
        supply_apy: u256,
        debt_amount: u256,
        debt_value: u256
    }

    struct UserAllowedBorrow has copy, drop {
        borrow_token: vector<u8>,
        max_borrow_amount: u256,
        max_borrow_value: u256,
        borrow_amount: u256,
        borrow_value: u256
    }

    struct UserAllowedWithdraw has copy, drop {
        withdraw_token: vector<u8>,
        max_withdraw_amount: u256,
        max_withdraw_value: u256,
        withdraw_amount: u256,
        withdraw_value: u256
    }

    struct UserTotalAllowedBorrow has copy, drop {
        total_allowed_borrow: vector<UserTotalBorrowInfo>
    }

    struct UserTotalBorrowInfo has copy, drop {
        dola_pool_id: u16,
        total_avaliable_borrow_amount: u256,
        total_avaliable_borrow_value: u256
    }


    struct DolaUserId has copy, drop {
        dola_user_id: u64
    }

    struct DolaUserAddresses has copy, drop {
        dola_user_addresses: vector<DolaAddress>
    }

    struct UserHealthFactor has copy, drop {
        health_factor: u256
    }

    struct UserAllDebts has copy, drop {
        dola_pool_ids: vector<u16>
    }

    struct UserAllCollaterals has copy, drop {
        dola_pool_ids: vector<u16>
    }

    struct TokenPrice has copy, drop {
        dola_pool_id: u16,
        price: u256,
        decimal: u8
    }

    struct AllTokenPrice has copy, drop {
        token_prices: vector<TokenPrice>
    }

    struct LiquidationDiscount has copy, drop {
        discount: u256
    }

    struct FeedTokens has copy, drop {
        dola_pool_ids: vector<u16>
    }

    public entry fun get_dola_token_liquidity(pool_manager_info: &mut PoolManagerInfo, dola_pool_id: u16) {
        let token_liquidity = pool_manager::get_token_liquidity(pool_manager_info, dola_pool_id);
        emit(TokenLiquidityInfo {
            dola_pool_id,
            token_liquidity
        })
    }

    public entry fun get_dola_user_id(user_manager_info: &mut UserManagerInfo, dola_chain_id: u16, user: vector<u8>) {
        let dola_address = dola_address::create_dola_address(dola_chain_id, user);
        let dola_user_id = user_manager::get_dola_user_id(user_manager_info, dola_address);
        emit(DolaUserId {
            dola_user_id
        })
    }

    public entry fun get_dola_user_addresses(
        user_manager_info: &mut UserManagerInfo,
        dola_user_id: u64
    ) {
        let dola_user_addresses = user_manager::get_user_addresses(user_manager_info, dola_user_id);
        emit(DolaUserAddresses {
            dola_user_addresses
        })
    }

    public entry fun get_app_token_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        app_id: u16,
        dola_pool_id: u16
    ) {
        let token_liquidity = pool_manager::get_app_liquidity(pool_manager_info, dola_pool_id, app_id);
        emit(AppLiquidityInfo {
            app_id,
            dola_pool_id,
            token_liquidity
        })
    }

    public entry fun get_pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        dola_chain_id: u16,
        pool_address: vector<u8>
    ) {
        let pool_address = dola_address::create_dola_address(dola_chain_id, pool_address);
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
        let pool_equilibrium_fee = pool_manager::get_pool_equilibrium_fee(pool_manager_info, pool_address);
        let pool_weight = pool_manager::get_pool_weight(pool_manager_info, pool_address);
        emit(PoolLiquidityInfo {
            pool_address,
            pool_liquidity,
            pool_equilibrium_fee,
            pool_weight
        })
    }

    public fun all_pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        dola_pool_id: u16
    ): vector<PoolLiquidityInfo> {
        let pool_addresses = pool_manager::get_pools_by_id(pool_manager_info, dola_pool_id);
        let length = vector::length(&pool_addresses);
        let i = 0;
        let pool_infos = vector::empty<PoolLiquidityInfo>();
        while (i < length) {
            let pool_address = *vector::borrow(&pool_addresses, i);
            let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
            let pool_equilibrium_fee = pool_manager::get_pool_equilibrium_fee(pool_manager_info, pool_address);
            let pool_weight = pool_manager::get_pool_weight(pool_manager_info, pool_address);
            let pool_info = PoolLiquidityInfo {
                pool_address,
                pool_liquidity,
                pool_equilibrium_fee,
                pool_weight
            };
            vector::push_back(&mut pool_infos, pool_info);
            i = i + 1;
        };
        pool_infos
    }

    public entry fun get_all_pool_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        dola_pool_id: u16
    ) {
        let pool_infos = all_pool_liquidity(pool_manager_info, dola_pool_id);
        emit(AllPoolLiquidityInfo {
            pool_infos
        })
    }

    public entry fun get_user_health_factor(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64
    ) {
        let health_factor = logic::user_health_factor(storage, oracle, dola_user_id);
        emit(UserHealthFactor {
            health_factor
        })
    }

    public entry fun get_user_all_debt(storage: &mut Storage, dola_user_id: u64) {
        let dola_pool_ids = storage::get_user_loans(storage, dola_user_id);
        emit(UserAllDebts {
            dola_pool_ids
        })
    }

    public entry fun get_user_token_debt(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let borrow_rate = storage::get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / ray_math::ray();
        let liquidity_rate = storage::get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / ray_math::ray();
        let debt_amount = logic::user_loan_balance(storage, dola_user_id, dola_pool_id);
        let debt_value = logic::user_loan_value(storage, oracle, dola_user_id, dola_pool_id);
        emit(UserDebtInfo {
            dola_pool_id,
            borrow_apy,
            supply_apy,
            debt_amount,
            debt_value
        })
    }

    public entry fun get_user_all_collateral(storgae: &mut Storage, dola_user_id: u64) {
        let dola_pool_ids = storage::get_user_collaterals(storgae, dola_user_id);
        emit(UserAllCollaterals {
            dola_pool_ids
        })
    }

    public entry fun get_user_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16
    ) {
        let borrow_rate = storage::get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / ray_math::ray();
        let liquidity_rate = storage::get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / ray_math::ray();
        let collateral_amount = logic::user_collateral_balance(storage, dola_user_id, dola_pool_id);
        let collateral_value = logic::user_collateral_value(storage, oracle, dola_user_id, dola_pool_id);
        emit(UserCollateralInfo {
            dola_pool_id,
            borrow_apy,
            supply_apy,
            collateral_amount,
            collateral_value
        })
    }

    public entry fun get_user_lending_info(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
    ) {
        let liquid_asset_infos = vector::empty<UserLiquidAssetInfo>();
        let liquid_assets = storage::get_user_liquid_assets(storage, dola_user_id);
        let total_liquid_value = 0;

        let collateral_infos = vector::empty<UserCollateralInfo>();
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let total_collateral_value = 0;

        let debt_infos = vector::empty<UserDebtInfo>();
        let loans = storage::get_user_loans(storage, dola_user_id);
        let total_debt_value = 0;

        let total_supply_apy_value = 0;
        let total_borrow_apy_value = 0;

        let length = vector::length(&liquid_assets);
        let i = 0;
        while (i < length) {
            let liquid_asset = vector::borrow(&liquid_assets, i);
            let borrow_rate = storage::get_borrow_rate(storage, *liquid_asset);
            let borrow_apy = borrow_rate * 10000 / ray_math::ray();
            let liquidity_rate = storage::get_liquidity_rate(storage, *liquid_asset);
            let supply_apy = liquidity_rate * 10000 / ray_math::ray();
            let liquid_amount = logic::user_collateral_balance(storage, dola_user_id, *liquid_asset);
            let liquid_value = logic::user_collateral_value(storage, oracle, dola_user_id, *liquid_asset);
            total_supply_apy_value = total_supply_apy_value + ray_math::ray_mul(liquid_value, liquidity_rate);
            vector::push_back(&mut liquid_asset_infos, UserLiquidAssetInfo {
                dola_pool_id: *liquid_asset,
                borrow_apy,
                supply_apy,
                liquid_amount,
                liquid_value
            });
            total_liquid_value = total_liquid_value + liquid_value;
            i = i + 1;
        };

        let length = vector::length(&collaterals);
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let borrow_rate = storage::get_borrow_rate(storage, *collateral);
            let borrow_apy = borrow_rate * 10000 / ray_math::ray();
            let liquidity_rate = storage::get_liquidity_rate(storage, *collateral);
            let supply_apy = liquidity_rate * 10000 / ray_math::ray();
            let collateral_amount = logic::user_collateral_balance(storage, dola_user_id, *collateral);
            let collateral_value = logic::user_collateral_value(storage, oracle, dola_user_id, *collateral);
            total_supply_apy_value = total_supply_apy_value + ray_math::ray_mul(collateral_value, liquidity_rate);
            vector::push_back(&mut collateral_infos, UserCollateralInfo {
                dola_pool_id: *collateral,
                borrow_apy,
                supply_apy,
                collateral_amount,
                collateral_value
            });
            total_collateral_value = total_collateral_value + collateral_value;
            i = i + 1;
        };

        length = vector::length(&loans);
        i = 0;
        while (i < length) {
            let loan = vector::borrow(&loans, i);
            let borrow_rate = storage::get_borrow_rate(storage, *loan);
            let borrow_apy = borrow_rate * 10000 / ray_math::ray();
            let liquidity_rate = storage::get_liquidity_rate(storage, *loan);
            let supply_apy = liquidity_rate * 10000 / ray_math::ray();
            let debt_amount = logic::user_loan_balance(storage, dola_user_id, *loan);
            let debt_value = logic::user_loan_value(storage, oracle, dola_user_id, *loan);
            total_borrow_apy_value = total_borrow_apy_value + ray_math::ray_mul(debt_value, borrow_rate);
            vector::push_back(&mut debt_infos, UserDebtInfo {
                dola_pool_id: *loan,
                borrow_apy,
                supply_apy,
                debt_amount,
                debt_value
            });
            total_debt_value = total_debt_value + debt_value;
            i = i + 1;
        };
        let health_factor = logic::user_health_factor(storage, oracle, dola_user_id);

        let total_supply_apy = 0;
        let total_borrow_apy = 0;
        let profit_state;

        if (total_collateral_value > 0) {
            total_supply_apy = ray_math::ray_div(total_supply_apy_value, total_collateral_value);
        };

        if (total_debt_value > 0) {
            total_borrow_apy = ray_math::ray_div(total_borrow_apy_value, total_debt_value);
        };

        let net_apy_value = if (total_supply_apy_value >= total_borrow_apy_value) {
            profit_state = true;
            total_supply_apy_value - total_borrow_apy_value
        } else {
            profit_state = false;
            total_borrow_apy_value - total_supply_apy_value
        };

        let net_value = if (total_liquid_value + total_collateral_value >= total_debt_value) {
            total_liquid_value + total_collateral_value - total_debt_value
        } else {
            total_debt_value - (total_liquid_value + total_collateral_value)
        };

        let net_apy = if (net_value > 0) { ray_math::ray_div(net_apy_value, net_value) } else { 0 };

        net_apy = net_apy * 10000 / ray_math::ray();
        total_supply_apy = total_supply_apy * 10000 / ray_math::ray();
        total_borrow_apy = total_borrow_apy * 10000 / ray_math::ray();

        let isolation_mode = logic::is_isolation_mode(storage, dola_user_id);

        emit(UserLendingInfo {
            health_factor,
            profit_state,
            net_apy,
            total_supply_apy,
            total_borrow_apy,
            liquid_asset_infos,
            total_liquid_value,
            collateral_infos,
            total_collateral_value,
            debt_infos,
            total_debt_value,
            isolation_mode,
        })
    }

    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16
    ) {
        let pools = all_pool_liquidity(pool_manager_info, dola_pool_id);
        let total_pool_weight = pool_manager::get_pool_total_weight(pool_manager_info, dola_pool_id);
        let borrow_coefficient = storage::get_borrow_coefficient(storage, dola_pool_id);
        let collateral_coefficient = storage::get_collateral_coefficient(storage, dola_pool_id);
        let borrow_rate = storage::get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / ray_math::ray();
        let liquidity_rate = storage::get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / ray_math::ray();
        let supply = logic::total_otoken_supply(storage, dola_pool_id);
        let debt = logic::total_dtoken_supply(storage, dola_pool_id);
        let reserve = pool_manager::get_app_liquidity(pool_manager_info, dola_pool_id, storage::get_app_id(storage));
        let current_isolate_debt = storage::get_isolate_debt(storage, dola_pool_id);
        let isolate_debt_ceiling = storage::get_reserve_borrow_ceiling(storage, dola_pool_id);
        let is_isolate_asset = storage::is_isolated_asset(storage, dola_pool_id);
        let borrowable_in_isolation = storage::can_borrow_in_isolation(storage, dola_pool_id);

        let utilization_rate = 0;
        if (debt > 0) {
            let utilization = rates::calculate_utilization(storage, dola_pool_id, reserve);
            utilization_rate = utilization * 10000 / ray_math::ray();
        };

        emit(LendingReserveInfo {
            dola_pool_id,
            collateral_coefficient,
            borrow_coefficient,
            borrow_apy,
            supply_apy,
            reserve,
            supply,
            debt,
            utilization_rate,
            pools,
            current_isolate_debt,
            isolate_debt_ceiling,
            is_isolate_asset,
            borrowable_in_isolation,
            total_pool_weight
        })
    }

    public entry fun get_all_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage
    ) {
        let reserve_length = storage::get_reserve_length(storage);
        let reserve_infos = vector::empty<LendingReserveInfo>();
        let i = 0;
        while (i < reserve_length) {
            let dola_pool_id = (i as u16);
            let pools = all_pool_liquidity(pool_manager_info, dola_pool_id);
            let total_pool_weight = pool_manager::get_pool_total_weight(pool_manager_info, dola_pool_id);
            let borrow_coefficient = storage::get_borrow_coefficient(storage, dola_pool_id);
            let collateral_coefficient = storage::get_collateral_coefficient(storage, dola_pool_id);
            let borrow_rate = storage::get_borrow_rate(storage, dola_pool_id);
            let borrow_apy = borrow_rate * 10000 / ray_math::ray();
            let liquidity_rate = storage::get_liquidity_rate(storage, dola_pool_id);
            let supply_apy = liquidity_rate * 10000 / ray_math::ray();
            let supply = logic::total_otoken_supply(storage, dola_pool_id);
            let debt = logic::total_dtoken_supply(storage, dola_pool_id);
            let reserve = pool_manager::get_app_liquidity(
                pool_manager_info,
                dola_pool_id,
                storage::get_app_id(storage)
            );
            let current_isolate_debt = storage::get_isolate_debt(storage, dola_pool_id);
            let isolate_debt_ceiling = storage::get_reserve_borrow_ceiling(storage, dola_pool_id);
            let is_isolate_asset = storage::is_isolated_asset(storage, dola_pool_id);
            let borrowable_in_isolation = storage::can_borrow_in_isolation(storage, dola_pool_id);

            let utilization_rate = 0;
            if (debt > 0) {
                let utilization = rates::calculate_utilization(storage, dola_pool_id, reserve);
                utilization_rate = utilization * 10000 / ray_math::ray();
            };


            let reserve_info = LendingReserveInfo {
                dola_pool_id,
                collateral_coefficient,
                borrow_coefficient,
                borrow_apy,
                supply_apy,
                reserve,
                supply,
                debt,
                utilization_rate,
                pools,
                current_isolate_debt,
                isolate_debt_ceiling,
                is_isolate_asset,
                borrowable_in_isolation,
                total_pool_weight
            };
            vector::push_back(&mut reserve_infos, reserve_info);
            i = i + 1;
        };
        emit(AllReserveInfo {
            reserve_infos
        })
    }

    public entry fun get_oracle_price(oracle: &mut PriceOracle, dola_pool_id: u16) {
        let (price, decimal, _) = oracle::get_token_price(oracle, dola_pool_id);
        emit(TokenPrice {
            dola_pool_id,
            price,
            decimal
        })
    }

    public entry fun get_all_oracle_price(storage: &mut Storage, oracle: &mut PriceOracle) {
        let reserve_length = storage::get_reserve_length(storage);
        let token_prices = vector::empty<TokenPrice>();
        let i = 0;
        while (i < reserve_length) {
            let dola_pool_id = (i as u16);
            let (price, decimal, _) = oracle::get_token_price(oracle, dola_pool_id);
            let token_price = TokenPrice {
                dola_pool_id,
                price,
                decimal
            };
            vector::push_back(&mut token_prices, token_price);
            i = i + 1;
        };
        emit(AllTokenPrice {
            token_prices
        })
    }

    public entry fun get_liquidation_discount(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        liquidator: u64,
        violator: u64
    ) {
        let discount = logic::calculate_liquidation_discount(storage, oracle, liquidator, violator);
        emit(LiquidationDiscount {
            discount
        })
    }

    public entry fun get_equilibrium_reward(
        pool_manager_info: &mut PoolManagerInfo,
        dola_chain_id: u16,
        pool_address: vector<u8>,
        deposit_amount: u256
    ) {
        let dola_pool_address = dola_address::create_dola_address(dola_chain_id, pool_address);
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, dola_pool_address);
        let total_liquidity = pool_manager::get_token_liquidity(pool_manager_info, dola_pool_id);
        let current_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dola_pool_address);
        let pool_weight = pool_manager::get_pool_weight(pool_manager_info, dola_pool_address);
        let total_weight = pool_manager::get_pool_total_weight(pool_manager_info, dola_pool_id);
        let total_equilibrium_reward = pool_manager::get_pool_equilibrium_fee(pool_manager_info, dola_pool_address);
        let equilibrium_reward = equilibrium_fee::calculate_equilibrium_reward(
            total_liquidity,
            current_liquidity,
            deposit_amount,
            equilibrium_fee::calculate_expected_ratio(total_weight, pool_weight),
            total_equilibrium_reward,
            pool_manager::get_default_lambda_1()
        ) ;
        emit(LiquidityEquilibriumReward {
            reward: equilibrium_reward
        })
    }

    public entry fun get_equilibrium_fee(
        pool_manager_info: &mut PoolManagerInfo,
        dola_chain_id: u16,
        pool_address: vector<u8>,
        withdraw_amount: u256
    ) {
        let dola_pool_address = dola_address::create_dola_address(dola_chain_id, pool_address);
        let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, dola_pool_address);
        let total_liquidity = pool_manager::get_token_liquidity(pool_manager_info, dola_pool_id);
        let current_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, dola_pool_address);
        let pool_weight = pool_manager::get_pool_weight(pool_manager_info, dola_pool_address);
        let total_weight = pool_manager::get_pool_total_weight(pool_manager_info, dola_pool_id);
        let equilibrium_fee = equilibrium_fee::calculate_equilibrium_fee(
            total_liquidity,
            current_liquidity,
            withdraw_amount,
            equilibrium_fee::calculate_expected_ratio(total_weight, pool_weight),
            pool_manager::get_default_alpha_1(),
            pool_manager::get_default_lambda_1()
        );
        emit(LiquidityEquilibriumFee {
            fee: equilibrium_fee
        })
    }

    public entry fun calculate_changed_health_factor(
        storage: &mut Storage,
        price_oracle: &mut PriceOracle,
        dola_user_id: u64,
        dola_pool_id: u16,
        amount: u256,
        is_supply: bool,
        is_borrow: bool,
        is_withdraw: bool,
        is_repay: bool,
        is_as_collateral: bool,
        is_cancel_collateral: bool,
    ) {
        let health_collateral_value = logic::user_health_collateral_value(storage, price_oracle, dola_user_id);
        let health_loan_value = logic::user_health_loan_value(storage, price_oracle, dola_user_id);

        let collateral_coefficient = storage::get_collateral_coefficient(storage, dola_pool_id);
        let borrow_coefficient = storage::get_borrow_coefficient(storage, dola_pool_id);

        if (is_supply) {
            let amount_value = logic::calculate_value(price_oracle, dola_pool_id, amount);
            health_collateral_value = health_collateral_value + ray_math::ray_mul(amount_value, collateral_coefficient);
        };

        if (is_borrow) {
            let amount_value = logic::calculate_value(price_oracle, dola_pool_id, amount);
            health_loan_value = health_loan_value + ray_math::ray_mul(amount_value, borrow_coefficient);
        };

        if (is_withdraw) {
            let balance = logic::user_collateral_balance(storage, dola_user_id, dola_pool_id);
            amount = ray_math::min(amount, balance);
            let amount_value = logic::calculate_value(price_oracle, dola_pool_id, amount);
            health_collateral_value = health_collateral_value - ray_math::ray_mul(amount_value, collateral_coefficient);
        };

        if (is_repay) {
            let balance = logic::user_loan_balance(storage, dola_user_id, dola_pool_id);
            amount = ray_math::min(amount, balance);
            let amount_value = logic::calculate_value(price_oracle, dola_pool_id, amount);
            health_loan_value = health_loan_value - ray_math::ray_mul(amount_value, borrow_coefficient);
            if (amount > balance) {
                let excess_repay = amount - balance;
                let excess_repay_value = logic::calculate_value(price_oracle, dola_pool_id, excess_repay);
                health_collateral_value = health_collateral_value + ray_math::ray_mul(
                    excess_repay_value,
                    collateral_coefficient
                );
            }
        };

        if (is_as_collateral) {
            let balance_value = logic::user_collateral_value(storage, price_oracle, dola_user_id, dola_pool_id);
            health_collateral_value = health_collateral_value + ray_math::ray_mul(
                balance_value,
                collateral_coefficient
            );
        };

        if (is_cancel_collateral) {
            let balance_value = logic::user_collateral_value(storage, price_oracle, dola_user_id, dola_pool_id);
            health_collateral_value = health_collateral_value - ray_math::ray_mul(
                balance_value,
                collateral_coefficient
            );
        };

        let health_factor = if (health_loan_value > 0) {
            ray_math::ray_div(health_collateral_value, health_loan_value)
        } else {
            U256_MAX
        };

        emit(UserHealthFactor {
            health_factor
        })
    }

    public fun get_feed_tokens_for_relayer(
        pool_manager_info: &mut PoolManagerInfo,
        user_manager_info: &mut UserManagerInfo,
        wormhole_state: &mut State,
        storage: &mut Storage,
        price_oracle: &mut PriceOracle,
        vaa: vector<u8>,
        is_withdraw: bool,
        is_liquidate: bool,
        is_cancel_collateral: bool,
        clock: &Clock
    ): vector<u16> {
        let vaa = vaa::parse_and_verify(wormhole_state, vaa, clock);
        let payload = vaa::take_payload(vaa);
        let dola_pool_ids = vector[];

        if (is_withdraw) {
            let (user_address, _, _, app_payload) =
                pool_codec::decode_send_message_payload(payload);
            let (_, _, _, pool, _, _) = lending_codec::decode_withdraw_payload(
                app_payload
            );
            let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
            let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
            let collaterals = storage::get_user_collaterals(storage, dola_user_id);
            let loans = storage::get_user_loans(storage, dola_user_id);
            if (!vector::contains(&loans, &dola_pool_id)) {
                vector::push_back(&mut dola_pool_ids, dola_pool_id);
            };

            if (vector::length(&loans) > 0) {
                vector::append(&mut dola_pool_ids, collaterals);
                vector::append(&mut dola_pool_ids, loans);
            };
        };

        if (is_liquidate) {
            let (_, _, _, _, _, app_payload) =
                pool_codec::decode_deposit_payload(payload);
            let (_, _, _, liquidate_user_id, _) = lending_codec::decode_liquidate_payload(
                app_payload
            );
            let collaterals = storage::get_user_collaterals(storage, liquidate_user_id);
            let loans = storage::get_user_loans(storage, liquidate_user_id);

            vector::append(&mut dola_pool_ids, collaterals);
            vector::append(&mut dola_pool_ids, loans);
        };

        if (is_cancel_collateral) {
            let (user_address, _, _, _) =
                pool_codec::decode_send_message_payload(payload);
            let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
            let collaterals = storage::get_user_collaterals(storage, dola_user_id);
            let loans = storage::get_user_loans(storage, dola_user_id);

            if (vector::length(&loans) > 0) {
                vector::append(&mut dola_pool_ids, collaterals);
                vector::append(&mut dola_pool_ids, loans);
            };
        };

        let current_timestamp = clock::timestamp_ms(clock) / 1000;
        let (ok, index) = vector::index_of(&dola_pool_ids, &1);
        if (ok) {
            let (_, _, timestamp) = oracle::get_token_price(price_oracle, 1);
            if (current_timestamp - timestamp < HOUR - MINUATE) {
                vector::remove(&mut dola_pool_ids, index);
            }
        };
        let (ok, index) = vector::index_of(&dola_pool_ids, &2);
        if (ok) {
            let (_, _, timestamp) = oracle::get_token_price(price_oracle, 2);
            if (current_timestamp - timestamp < HOUR - MINUATE) {
                vector::remove(&mut dola_pool_ids, index);
            }
        };
        dola_pool_ids
    }

    public entry fun get_feed_tokens(
        storage: &mut Storage,
        price_oracle: &mut PriceOracle,
        dola_user_id: u64,
        is_borrow: bool,
        borrow_pool_id: u16,
        clock: &Clock
    ) {
        let collaterals = storage::get_user_collaterals(storage, dola_user_id);
        let loans = storage::get_user_loans(storage, dola_user_id);
        let dola_pool_ids = vector[];
        if (is_borrow) {
            if (!vector::contains(&loans, &borrow_pool_id)) {
                vector::push_back(&mut dola_pool_ids, borrow_pool_id)
            };
            vector::append(&mut dola_pool_ids, collaterals);
            vector::append(&mut dola_pool_ids, loans);
        } else {
            if (vector::length(&loans) > 0) {
                vector::append(&mut dola_pool_ids, collaterals);
                vector::append(&mut dola_pool_ids, loans);
            }
        };

        let current_timestamp = clock::timestamp_ms(clock) / 1000;
        let (ok, index) = vector::index_of(&dola_pool_ids, &1);
        if (ok) {
            let (_, _, timestamp) = oracle::get_token_price(price_oracle, 1);
            if (current_timestamp - timestamp < HOUR - MINUATE) {
                vector::remove(&mut dola_pool_ids, index);
            }
        };
        let (ok, index) = vector::index_of(&dola_pool_ids, &2);
        if (ok) {
            let (_, _, timestamp) = oracle::get_token_price(price_oracle, 2);
            if (current_timestamp - timestamp < HOUR - MINUATE) {
                vector::remove(&mut dola_pool_ids, index);
            }
        };

        emit(FeedTokens {
            dola_pool_ids
        })
    }

    public entry fun get_user_allowed_withdraw(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16,
        dola_user_id: u64,
        withdraw_pool_id: u16,
    ) {
        let withdraw_token = into_bytes(pool_manager::get_pool_name_by_id(pool_manager_info, withdraw_pool_id));
        let health_collateral_value = logic::user_health_collateral_value(storage, oracle, dola_user_id);
        let health_loan_value = ray_math::ray_mul(
            logic::user_health_loan_value(storage, oracle, dola_user_id),
            TARGET_HF
        );
        let collateral_coefficient = storage::get_collateral_coefficient(storage, withdraw_pool_id);
        let can_withdraw_value = ray_math::ray_div(
            (health_collateral_value - health_loan_value),
            collateral_coefficient
        );
        let withdraw_amount = logic::calculate_amount(oracle, withdraw_pool_id, can_withdraw_value);
        let pool_address = pool_manager::find_pool_by_chain(pool_manager_info, withdraw_pool_id, dola_chain_id);

        let pool_liquidity = 0;
        if (option::is_some(&pool_address)) {
            let pool_address = option::extract(&mut pool_address);
            pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
        };
        let reserve = pool_manager::get_app_liquidity(
            pool_manager_info,
            withdraw_pool_id,
            storage::get_app_id(storage)
        );

        let max_withdraw_amount = ray_math::min(withdraw_amount, reserve);
        withdraw_amount = ray_math::min(withdraw_amount, pool_liquidity);
        let max_withdraw_value = logic::calculate_value(oracle, withdraw_pool_id, max_withdraw_amount);
        let withdraw_value = logic::calculate_value(oracle, withdraw_pool_id, withdraw_amount);
        emit(UserAllowedWithdraw {
            withdraw_token,
            max_withdraw_amount,
            max_withdraw_value,
            withdraw_amount,
            withdraw_value
        })
    }

    public entry fun get_user_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16,
        dola_user_id: u64,
        borrow_pool_id: u16,
    ) {
        let borrow_token = into_bytes(pool_manager::get_pool_name_by_id(pool_manager_info, borrow_pool_id));
        let health_collateral_value = logic::user_health_collateral_value(storage, oracle, dola_user_id);
        let health_loan_value = ray_math::ray_mul(
            logic::user_health_loan_value(storage, oracle, dola_user_id),
            TARGET_HF
        );
        let borrow_coefficient = storage::get_borrow_coefficient(storage, borrow_pool_id);
        let can_borrow_value = ray_math::ray_div(
            (health_collateral_value - health_loan_value),
            borrow_coefficient
        );
        let borrow_amount = logic::calculate_amount(oracle, borrow_pool_id, can_borrow_value);
        let pool_address = pool_manager::find_pool_by_chain(pool_manager_info, borrow_pool_id, dola_chain_id);

        let pool_liquidity = 0;
        if (option::is_some(&pool_address)) {
            let pool_address = option::extract(&mut pool_address);
            pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
        };
        let reserve = pool_manager::get_app_liquidity(pool_manager_info, borrow_pool_id, storage::get_app_id(storage));

        let max_borrow_amount = ray_math::min(borrow_amount, reserve);
        borrow_amount = ray_math::min(borrow_amount, pool_liquidity);
        let max_borrow_value = logic::calculate_value(oracle, borrow_pool_id, max_borrow_amount);
        let borrow_value = logic::calculate_value(oracle, borrow_pool_id, borrow_amount);
        emit(UserAllowedBorrow {
            borrow_token,
            max_borrow_amount,
            max_borrow_value,
            borrow_amount,
            borrow_value
        })
    }

    public entry fun get_user_total_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
    ) {
        let reserve_length = storage::get_reserve_length(storage);

        let user_total_allowed_borrow = vector::empty<UserTotalBorrowInfo>();

        let i = 0;
        while (i < reserve_length) {
            let borrow_pool_id = (i as u16);
            let health_collateral_value = logic::user_health_collateral_value(storage, oracle, dola_user_id);
            let health_loan_value = ray_math::ray_mul(
                logic::user_health_loan_value(storage, oracle, dola_user_id),
                TARGET_HF
            );
            let borrow_coefficient = storage::get_borrow_coefficient(storage, borrow_pool_id);
            let can_borrow_value = ray_math::ray_div(
                (health_collateral_value - health_loan_value),
                borrow_coefficient
            );
            let reserve = pool_manager::get_app_liquidity(
                pool_manager_info,
                borrow_pool_id,
                storage::get_app_id(storage)
            );

            let borrow_amount = logic::calculate_amount(oracle, borrow_pool_id, can_borrow_value);


            let total_avaliable_borrow_amount = ray_math::min(borrow_amount, reserve);
            let total_avaliable_borrow_value = logic::calculate_value(
                oracle,
                borrow_pool_id,
                total_avaliable_borrow_amount
            );

            let user_total_borrow_info = UserTotalBorrowInfo {
                dola_pool_id: borrow_pool_id,
                total_avaliable_borrow_amount,
                total_avaliable_borrow_value
            };
            vector::push_back(&mut user_total_allowed_borrow, user_total_borrow_info);
            i = i + 1;
        };
        emit(
            UserTotalAllowedBorrow {
                total_allowed_borrow: user_total_allowed_borrow
            }
        )
    }
}
