// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0

/// Unified external call interface to get data
/// by simulating calls to trigger events.
module external_interfaces::interfaces {
    use std::ascii::into_bytes;
    use std::vector;

    use sui::clock::{Self, Clock};
    use sui::event::emit;
    use sui::object;

    use dola_protocol::boost;
    use dola_protocol::dola_address::{Self, DolaAddress};
    use dola_protocol::equilibrium_fee;
    use dola_protocol::lending_codec;
    use dola_protocol::lending_core_storage::{Self as storage, Storage};
    use dola_protocol::lending_logic;
    use dola_protocol::lending_logic as logic;
    use dola_protocol::lending_logic::{is_liquid_asset, user_collateral_value};
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

    const SECONDS_PER_YEAR: u256 = 31536000;

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
        available_value: u256,
        supply: u256,
        supply_value: u256,
        debt: u256,
        debt_value: u256,
        current_isolate_debt: u256,
        isolate_debt_ceiling: u256,
        is_isolate_asset: bool,
        borrowable_in_isolation: bool,
        utilization_rate: u256
    }

    struct AllReserveInfo has copy, drop {
        total_market_size: u256,
        total_available: u256,
        total_borrows: u256,
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
        feed_pool_ids: vector<u16>,
        skip_pool_ids: vector<u16>,
    }

    struct RewardPoolApy has copy, drop {
        reward_pool_info: address,
        apy: u256
    }

    struct RewardPoolApys has copy, drop {
        apys: vector<RewardPoolApy>
    }

    struct UserTotalRewardInfo has copy, drop {
        total_reward: u256,
        total_reward_value: u256,
        total_unclaimed_reward: u256,
        total_unclaimed_reward_value: u256,
        user_reward_infos: vector<UserRewardInfo>,
    }

    struct UserRewardInfo has copy, drop {
        dola_pool_id: u16,
        action: u8,
        reward_pool_info: address,
        unclaimed_reward: u256,
        unclaimed_reward_value: u256,
        claimed_reward: u256,
        claimed_reward_value: u256,
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
        let pool_infos = vector::empty<PoolLiquidityInfo>();
        if (pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
            let pool_addresses = pool_manager::get_pools_by_id(pool_manager_info, dola_pool_id);
            let length = vector::length(&pool_addresses);
            let i = 0;
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
        oracle: &mut PriceOracle,
        storage: &mut Storage,
        dola_pool_id: u16
    ) {
        let pools = all_pool_liquidity(pool_manager_info, dola_pool_id);
        let total_pool_weight = if (pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
            pool_manager::get_pool_total_weight(pool_manager_info, dola_pool_id)
        } else {
            0
        };
        let borrow_coefficient = storage::get_borrow_coefficient(storage, dola_pool_id);
        let reserve = if (pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
            pool_manager::get_app_liquidity(
                pool_manager_info,
                dola_pool_id,
                storage::get_app_id(storage)
            )
        }else {
            0
        };
        let available_value = logic::calculate_value(oracle, dola_pool_id, reserve);
        let collateral_coefficient = storage::get_collateral_coefficient(storage, dola_pool_id);
        let borrow_rate = storage::get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / ray_math::ray();
        let liquidity_rate = storage::get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / ray_math::ray();
        let supply = logic::total_otoken_supply(storage, dola_pool_id);
        let supply_value = logic::calculate_value(oracle, dola_pool_id, supply);
        let debt = logic::total_dtoken_supply(storage, dola_pool_id);
        let debt_value = logic::calculate_value(oracle, dola_pool_id, debt);
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
            available_value,
            supply,
            supply_value,
            debt,
            debt_value,
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
        oracle: &mut PriceOracle,
        storage: &mut Storage
    ) {
        let reserve_length = storage::get_reserve_length(storage);
        let reserve_infos = vector::empty<LendingReserveInfo>();
        let total_market_size = 0;
        let total_available = 0;
        let total_borrows = 0;

        let i = 0;
        while (i < reserve_length) {
            let dola_pool_id = (i as u16);
            let pools = all_pool_liquidity(pool_manager_info, dola_pool_id);
            let total_pool_weight = if (pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
                pool_manager::get_pool_total_weight(pool_manager_info, dola_pool_id)
            } else {
                0
            };
            let borrow_coefficient = storage::get_borrow_coefficient(storage, dola_pool_id);
            let collateral_coefficient = storage::get_collateral_coefficient(storage, dola_pool_id);
            let borrow_rate = storage::get_borrow_rate(storage, dola_pool_id);
            let borrow_apy = borrow_rate * 10000 / ray_math::ray();
            let liquidity_rate = storage::get_liquidity_rate(storage, dola_pool_id);
            let supply_apy = liquidity_rate * 10000 / ray_math::ray();
            let supply = logic::total_otoken_supply(storage, dola_pool_id);
            let supply_value = logic::calculate_value(oracle, dola_pool_id, supply);
            let debt = logic::total_dtoken_supply(storage, dola_pool_id);
            let debt_value = logic::calculate_value(oracle, dola_pool_id, debt);
            let reserve = if (pool_manager::exist_pool_id(pool_manager_info, dola_pool_id)) {
                pool_manager::get_app_liquidity(
                    pool_manager_info,
                    dola_pool_id,
                    storage::get_app_id(storage)
                )
            }else {
                0
            };
            let available_value = logic::calculate_value(oracle, dola_pool_id, reserve);
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
                available_value,
                supply,
                supply_value,
                debt,
                debt_value,
                utilization_rate,
                pools,
                current_isolate_debt,
                isolate_debt_ceiling,
                is_isolate_asset,
                borrowable_in_isolation,
                total_pool_weight
            };
            vector::push_back(&mut reserve_infos, reserve_info);

            total_market_size = total_market_size + supply_value;
            total_available = total_available + available_value;
            total_borrows = total_borrows + debt_value;

            i = i + 1;
        };
        emit(AllReserveInfo {
            total_market_size,
            total_available,
            total_borrows,
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
        if (!storage::exist_user_info(storage, dola_user_id)) {
            emit(UserHealthFactor {
                health_factor: U256_MAX
            });
            return
        };

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
    ): (vector<u16>, vector<u16>) {
        let vaa = vaa::parse_and_verify(wormhole_state, vaa, clock);
        let payload = vaa::take_payload(vaa);
        let feed_pool_ids = vector[];
        let skip_pool_ids = vector[];

        if (is_withdraw) {
            let (user_address, _, _, app_payload) =
                pool_codec::decode_send_message_payload(payload);
            let (_, _, _, pool, _, call_type) = lending_codec::decode_withdraw_payload(
                app_payload
            );
            let dola_pool_id = pool_manager::get_id_by_pool(pool_manager_info, pool);
            let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
            let collaterals = storage::get_user_collaterals(storage, dola_user_id);
            let loans = storage::get_user_loans(storage, dola_user_id);
            if (!vector::contains(&loans, &dola_pool_id)) {
                vector::push_back(&mut feed_pool_ids, dola_pool_id);
            };

            if (vector::length(&loans) > 0 || call_type == lending_codec::get_borrow_type()) {
                vector::append(&mut feed_pool_ids, collaterals);
                vector::append(&mut feed_pool_ids, loans);
            };
        };

        if (is_liquidate) {
            let (sender, _, _, app_payload) =
                pool_codec::decode_send_message_payload(payload);
            let (_, _, _, liquidate_user_id, _, _) = lending_codec::decode_liquidate_payload_v2(
                app_payload
            );
            let sender_dola_user_id = user_manager::get_dola_user_id(user_manager_info, sender);
            let sender_collaterals = storage::get_user_collaterals(storage, sender_dola_user_id);
            let sender_loans = storage::get_user_loans(storage, sender_dola_user_id);

            vector::append(&mut feed_pool_ids, sender_collaterals);
            vector::append(&mut feed_pool_ids, sender_loans);

            let collaterals = storage::get_user_collaterals(storage, liquidate_user_id);
            let loans = storage::get_user_loans(storage, liquidate_user_id);

            vector::append(&mut feed_pool_ids, collaterals);
            vector::append(&mut feed_pool_ids, loans);
        };

        if (is_cancel_collateral) {
            let (user_address, _, _, _) =
                pool_codec::decode_send_message_payload(payload);
            let dola_user_id = user_manager::get_dola_user_id(user_manager_info, user_address);
            let collaterals = storage::get_user_collaterals(storage, dola_user_id);
            let loans = storage::get_user_loans(storage, dola_user_id);

            if (vector::length(&loans) > 0) {
                vector::append(&mut feed_pool_ids, collaterals);
                vector::append(&mut feed_pool_ids, loans);
            };
        };

        let current_timestamp = clock::timestamp_ms(clock) / 1000;

        let usdt_pool_id = 1;
        let (_, _, timestamp) = oracle::get_token_price(price_oracle, usdt_pool_id);
        if (current_timestamp - timestamp < HOUR - MINUATE) {
            vector::push_back(&mut skip_pool_ids, usdt_pool_id);
        };

        let usdc_pool_id = 2;
        let (_, _, timestamp) = oracle::get_token_price(price_oracle, usdc_pool_id);
        if (current_timestamp - timestamp < HOUR - MINUATE) {
            vector::push_back(&mut skip_pool_ids, usdc_pool_id);
        };

        (feed_pool_ids, skip_pool_ids)
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
        let feed_pool_ids = vector[];
        let skip_pool_ids = vector[];

        if (is_borrow) {
            if (!vector::contains(&loans, &borrow_pool_id)) {
                vector::push_back(&mut feed_pool_ids, borrow_pool_id)
            };
            vector::append(&mut feed_pool_ids, collaterals);
            vector::append(&mut feed_pool_ids, loans);
        } else {
            if (vector::length(&loans) > 0) {
                vector::append(&mut feed_pool_ids, collaterals);
                vector::append(&mut feed_pool_ids, loans);
            }
        };

        let current_timestamp = clock::timestamp_ms(clock) / 1000;

        let usdt_pool_id = 1;
        let (_, _, timestamp) = oracle::get_token_price(price_oracle, usdt_pool_id);
        if (current_timestamp - timestamp < HOUR - MINUATE) {
            vector::push_back(&mut skip_pool_ids, usdt_pool_id);
        };

        let usdc_pool_id = 2;
        let (_, _, timestamp) = oracle::get_token_price(price_oracle, usdc_pool_id);
        if (current_timestamp - timestamp < HOUR - MINUATE) {
            vector::push_back(&mut skip_pool_ids, usdc_pool_id);
        };

        emit(FeedTokens {
            feed_pool_ids,
            skip_pool_ids,
        })
    }

    public entry fun get_user_allowed_withdraw(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16,
        dola_address: vector<u8>,
        dola_user_id: u64,
        withdraw_pool_id: u16,
        withdarw_all: bool,
    ) {
        let withdraw_token = into_bytes(pool_manager::get_pool_name_by_id(pool_manager_info, withdraw_pool_id));

        let health_collateral_value = logic::user_health_collateral_value(storage, oracle, dola_user_id);

        let health_loan_value = logic::user_health_loan_value(storage, oracle, dola_user_id);
        let target_loan_value = ray_math::ray_mul(
            health_loan_value,
            TARGET_HF
        );

        let collateral_coefficient = storage::get_collateral_coefficient(storage, withdraw_pool_id);

        if (logic::user_health_factor(storage, oracle, dola_user_id) <= TARGET_HF) {
            emit(UserAllowedWithdraw {
                withdraw_token,
                max_withdraw_amount: 0,
                max_withdraw_value: 0,
                withdraw_amount: 0,
                withdraw_value: 0
            });
            return
        };

        let can_withdraw_value = if (is_liquid_asset(storage, dola_user_id, withdraw_pool_id)) {
            user_collateral_value(storage, oracle, dola_user_id, withdraw_pool_id)
        } else {
            ray_math::ray_div(
                (health_collateral_value - target_loan_value),
                collateral_coefficient
            )
        };
        let can_withdraw_amount = logic::calculate_amount(oracle, withdraw_pool_id, can_withdraw_value);
        let withdraw_amount = logic::user_collateral_balance(storage, dola_user_id, withdraw_pool_id);
        let withdraw_amount = ray_math::min(can_withdraw_amount, withdraw_amount);

        let pool_address = dola_address::create_dola_address(dola_chain_id, dola_address);

        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
        let reserve = pool_manager::get_app_liquidity(
            pool_manager_info,
            withdraw_pool_id,
            storage::get_app_id(storage)
        );

        let max_withdraw_amount = ray_math::min(withdraw_amount, reserve);

        if (withdarw_all && health_loan_value == 0) {
            withdraw_amount = withdraw_amount * 10;
        };

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
        dola_address: vector<u8>,
        dola_user_id: u64,
        borrow_pool_id: u16,
    ) {
        let borrow_token = into_bytes(pool_manager::get_pool_name_by_id(pool_manager_info, borrow_pool_id));
        let health_collateral_value = logic::user_health_collateral_value(storage, oracle, dola_user_id);

        let target_collateral_value = ray_math::ray_div(
            health_collateral_value,
            TARGET_HF
        );

        let health_loan_value = logic::user_health_loan_value(storage, oracle, dola_user_id);

        if (logic::user_health_factor(storage, oracle, dola_user_id) <= TARGET_HF) {
            emit(UserAllowedBorrow {
                borrow_token,
                max_borrow_amount: 0,
                max_borrow_value: 0,
                borrow_amount: 0,
                borrow_value: 0
            });
            return
        };

        let borrow_coefficient = storage::get_borrow_coefficient(storage, borrow_pool_id);
        let can_borrow_value = ray_math::ray_div(
            (target_collateral_value - health_loan_value),
            borrow_coefficient
        );
        let borrow_amount = logic::calculate_amount(oracle, borrow_pool_id, can_borrow_value);
        let pool_address = dola_address::create_dola_address(dola_chain_id, dola_address);

        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
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

    public fun get_user_rewrad(
        storage: &mut Storage,
        reward_pool_info: address,
        dola_user_id: u64,
        dola_pool_id: u16,
        clock: &Clock
    ): (u256, u256, u8) {
        let reward_pool_info = object::id_from_address(reward_pool_info);

        let unclaimed_balance;
        let claimed_balance;
        let reward_action;

        let reward_pools = boost::get_reward_pool_infos(storage, dola_pool_id);
        let reward_pool_info = boost::get_reward_pool(reward_pools, reward_pool_info);
        reward_action = boost::get_reward_action(reward_pool_info);
        let current_timestamp = ray_math::max(
            storage::get_timestamp(clock),
            boost::get_start_time(reward_pool_info)
        );
        let current_timestamp = ray_math::min(current_timestamp, boost::get_end_time(reward_pool_info));

        let old_timestamp = boost::get_last_update_time(reward_pool_info);
        let old_reward_index = boost::get_reward_index(reward_pool_info);
        let total_scaled_balance = boost::get_total_scaled_balance(
            storage,
            dola_pool_id,
            reward_action,
        );
        let new_reward_index;
        if (total_scaled_balance == 0) {
            new_reward_index = 0;
        } else {
            new_reward_index = old_reward_index + boost::get_reward_per_second(
                reward_pool_info
            ) * (current_timestamp - old_timestamp) / total_scaled_balance
        };
        let last_update_reward_index = 0;
        if (!boost::is_exist_user_reward(reward_pool_info, dola_user_id)) {
            unclaimed_balance = 0;
            claimed_balance = 0;
        }else {
            (unclaimed_balance, claimed_balance, last_update_reward_index) = boost::get_user_reward_info(
                reward_pool_info,
                dola_user_id,
            );
        };
        let delta_index = new_reward_index - last_update_reward_index;
        unclaimed_balance = unclaimed_balance + ray_math::ray_mul(
            delta_index,
            boost::get_user_scaled_balance(
                storage,
                dola_pool_id,
                dola_user_id,
                reward_action,
            )
        );

        (unclaimed_balance, claimed_balance, reward_action)
    }

    public fun get_user_total_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
    ) {
        let reserve_length = storage::get_reserve_length(storage);

        let user_total_allowed_borrow = vector::empty<UserTotalBorrowInfo>();


        let health_collateral_value = logic::user_health_collateral_value(storage, oracle, dola_user_id);

        let target_collateral_value = ray_math::ray_div(
            health_collateral_value,
            TARGET_HF
        );

        let health_loan_value = logic::user_health_loan_value(storage, oracle, dola_user_id);

        let health = true;
        if (logic::user_health_factor(storage, oracle, dola_user_id) <= TARGET_HF) {
            health = false;
        };

        let i = 0;
        while (i < reserve_length) {
            let borrow_pool_id = (i as u16);

            let borrow_coefficient = storage::get_borrow_coefficient(storage, borrow_pool_id);

            let can_borrow_value = if (health) {
                ray_math::ray_div(
                    (target_collateral_value - health_loan_value),
                    borrow_coefficient
                )
            } else { 0 };
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

    public entry fun get_user_total_reward_info(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_user_id: u64,
        reward_tokens: vector<u16>,
        dola_pool_ids: vector<u16>,
        reward_pool_infos: vector<address>,
        clock: &Clock
    ) {
        let total_reward = 0;
        let total_reward_value = 0;
        let total_unclaimed_reward = 0;
        let total_unclaimed_reward_value = 0;
        let user_reward_infos = vector::empty<UserRewardInfo>();

        let i = 0;
        while (i < vector::length(&dola_pool_ids)) {
            let dola_pool_id = *vector::borrow(&dola_pool_ids, i);
            let reward_pool_info = *vector::borrow(&reward_pool_infos, i);
            let reward_token = *vector::borrow(&reward_tokens, i);
            let (unclaimed_balance, claimed_balance, reward_action) = get_user_rewrad(
                storage,
                reward_pool_info,
                dola_user_id,
                dola_pool_id,
                clock,
            );
            let unclaimed_supply_reward = logic::calculate_value(oracle, reward_token, unclaimed_balance);
            let claimed_supply_reward = logic::calculate_value(oracle, reward_token, claimed_balance);

            total_reward = total_reward + unclaimed_balance + claimed_balance;
            total_reward_value = total_reward_value + unclaimed_supply_reward + claimed_supply_reward;
            total_unclaimed_reward = total_unclaimed_reward + unclaimed_balance;
            total_unclaimed_reward_value = total_unclaimed_reward_value + unclaimed_supply_reward;

            let user_reward_info = UserRewardInfo {
                dola_pool_id,
                action: reward_action,
                reward_pool_info,
                unclaimed_reward: unclaimed_balance,
                unclaimed_reward_value: unclaimed_supply_reward,
                claimed_reward: claimed_balance,
                claimed_reward_value: claimed_supply_reward,
            };
            vector::push_back(&mut user_reward_infos, user_reward_info);

            i = i + 1;
        };

        emit(
            UserTotalRewardInfo {
                total_reward,
                total_reward_value,
                total_unclaimed_reward,
                total_unclaimed_reward_value,
                user_reward_infos,
            }
        )
    }

    public fun get_reward_pool_apy(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        reward_token: u16,
        reward_pool_info: address,
        dola_pool_id: u16,
        clock: &Clock,
    ): u256 {
        let total_otoken_balance = lending_logic::total_otoken_supply(storage, dola_pool_id);
        let total_dtoken_balance = lending_logic::total_dtoken_supply(storage, dola_pool_id);

        let reward_pool_info = object::id_from_address(reward_pool_info);
        let apy;

        let reward_token_decimal;
        if (reward_token == 3) {
            reward_token_decimal = 9;
        }else if (dola_pool_id == 8) {
            reward_token_decimal = 6;
        }else {
            reward_token_decimal = 8;
        };

        let reward_pools = boost::get_reward_pool_infos(storage, dola_pool_id);
        let reward_pool_info = boost::get_reward_pool(reward_pools, reward_pool_info);
        let reward_action = boost::get_reward_action(reward_pool_info);
        let total_balance;
        if (reward_action == lending_codec::get_supply_type()) {
            total_balance = total_otoken_balance;
        }else {
            total_balance = total_dtoken_balance;
        };
        let total_value = logic::calculate_value(oracle, dola_pool_id, total_balance);

        let total_reward_balance = boost::get_reward_per_second(reward_pool_info) * SECONDS_PER_YEAR;
        if (reward_token_decimal > 8) {
            total_reward_balance = total_reward_balance / (sui::math::pow(10, reward_token_decimal - 8) as u256)
        }else if (reward_token_decimal < 8) {
            total_reward_balance = total_reward_balance * (sui::math::pow(10, 8 - reward_token_decimal) as u256)
        };
        let total_reward_value = logic::calculate_value(oracle, reward_token, total_reward_balance);

        if (total_value == 0 || storage::get_timestamp(clock) >= boost::get_end_time(reward_pool_info)) {
            apy = 0;
        }else {
            apy = total_reward_value * 10000 / total_value / ray_math::ray();
        };

        apy
    }

    public entry fun get_reward_pool_apys(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        reward_tokens: vector<u16>,
        reward_pool_infos: vector<address>,
        dola_pool_ids: vector<u16>,
        clock: &Clock
    ) {
        let apys = vector::empty<RewardPoolApy>();
        let i = 0;
        while (i < vector::length(&reward_pool_infos)) {
            let dola_pool_id = *vector::borrow(&dola_pool_ids, i);
            let reward_pool_info = *vector::borrow(&reward_pool_infos, i);
            let reward_token = *vector::borrow(&reward_tokens, i);

            let apy = get_reward_pool_apy(
                storage,
                oracle,
                reward_token,
                reward_pool_info,
                dola_pool_id,
                clock
            );
            vector::push_back(&mut apys, RewardPoolApy {
                reward_pool_info,
                apy
            });
            i = i + 1;
        };
        emit(RewardPoolApys {
            apys
        })
    }
}
