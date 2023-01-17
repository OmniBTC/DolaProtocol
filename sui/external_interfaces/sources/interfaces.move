/// Unified external call interface to get data
/// by simulating calls to trigger events.
module external_interfaces::interfaces {
    use std::ascii::{String, string, into_bytes};
    use std::option::{Self, Option};
    use std::vector;

    use dola_types::types::{create_dola_address, DolaAddress};
    use lending::logic::{user_loan_balance, user_loan_value, user_collateral_balance, user_collateral_value, total_dtoken_supply, is_collateral, calculate_value, user_health_factor, user_health_collateral_value, user_health_loan_value, calculate_amount, user_total_collateral_value, user_total_loan_value};
    use lending::math::{ray_mul, ray_div};
    use lending::rates::calculate_utilization;
    use lending::storage::{Storage, get_user_collaterals, get_user_loans, get_borrow_rate, get_liquidity_rate, get_app_id, get_reserve_length, get_borrow_coefficient, get_collateral_coefficient};
    use oracle::oracle::{PriceOracle, get_token_price};
    use pool_manager::pool_manager::{Self, get_token_liquidity, PoolManagerInfo, get_app_liquidity, get_pool_name_by_id, find_pool_by_chain};
    use sui::event::emit;
    use sui::math::min;
    use user_manager::user_manager::{Self, UserManagerInfo};

    const RAY: u64 = 100000000;

    struct TokenLiquidityInfo has copy, drop {
        dola_pool_id: u16,
        token_liquidity: u64,
    }

    struct AppLiquidityInfo has copy, drop {
        app_id: u16,
        dola_pool_id: u16,
        token_liquidity: u128,
    }

    struct PoolLiquidityInfo has copy, drop {
        pool_address: DolaAddress,
        pool_liquidity: u64
    }

    struct AllPoolLiquidityInfo has copy, drop {
        pool_infos: vector<PoolLiquidityInfo>
    }

    struct LendingReserveInfo has copy, drop {
        dola_pool_id: u16,
        pools: vector<PoolLiquidityInfo>,
        collateral_coefficient: u64,
        borrow_coefficient: u64,
        borrow_apy: u64,
        supply_apy: u64,
        reserve: u128,
        debt: u128,
        utilization_rate: u64
    }

    struct AllReserveInfo has copy, drop {
        reserve_infos: vector<LendingReserveInfo>
    }

    struct UserLendingInfo has copy, drop {
        health_factor: u64,
        profit_state: bool,
        net_apy: u64,
        total_supply_apy: u64,
        total_borrow_apy: u64,
        collateral_infos: vector<UserCollateralInfo>,
        total_collateral_value: u64,
        debt_infos: vector<UserDebtInfo>,
        total_debt_value: u64
    }

    struct UserCollateralInfo has copy, drop {
        dola_pool_id: u16,
        borrow_apy: u64,
        supply_apy: u64,
        collateral_amount: u64,
        collateral_value: u64
    }

    struct UserDebtInfo has copy, drop {
        dola_pool_id: u16,
        borrow_apy: u64,
        supply_apy: u64,
        debt_amount: u64,
        debt_value: u64
    }

    struct UserAllowedBorrow has copy, drop {
        borrow_token: vector<u8>,
        max_borrow_amount: u64,
        max_borrow_value: u64,
        borrow_amount: u64,
        borrow_value: u64,
        reason: Option<String>
    }

    struct DolaUserId has copy, drop {
        dola_user_id: u64
    }

    struct DolaUserAddresses has copy, drop {
        dola_user_addresses: vector<DolaAddress>
    }

    struct UserHealthFactor has copy, drop {
        health_factor: u64
    }

    struct UserAllDebts has copy, drop {
        dola_pool_ids: vector<u16>
    }

    struct UserAllCollaterals has copy, drop {
        dola_pool_ids: vector<u16>
    }

    struct TokenPrice has copy, drop {
        dola_pool_id: u16,
        price: u64,
        decimal: u8
    }

    struct AllTokenPrice has copy, drop {
        token_prices: vector<TokenPrice>
    }

    public entry fun get_dola_token_liquidity(pool_manager_info: &mut PoolManagerInfo, dola_pool_id: u16) {
        let token_liquidity = get_token_liquidity(pool_manager_info, dola_pool_id);
        emit(TokenLiquidityInfo {
            dola_pool_id,
            token_liquidity
        })
    }

    public entry fun get_dola_user_id(user_manager_info: &mut UserManagerInfo, dola_chain_id: u16, user: vector<u8>) {
        let dola_address = create_dola_address(dola_chain_id, user);
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
        let token_liquidity = get_app_liquidity(pool_manager_info, dola_pool_id, app_id);
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
        let pool_address = create_dola_address(dola_chain_id, pool_address);
        let pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
        emit(PoolLiquidityInfo {
            pool_address,
            pool_liquidity
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
            let pool_info = PoolLiquidityInfo {
                pool_address,
                pool_liquidity
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
        let health_factor = user_health_factor(storage, oracle, dola_user_id);
        emit(UserHealthFactor {
            health_factor
        })
    }

    public entry fun get_user_all_debt(storage: &mut Storage, dola_user_id: u64) {
        let dola_pool_ids = get_user_loans(storage, dola_user_id);
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
        let borrow_rate = get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / RAY;
        let liquidity_rate = get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / RAY;
        let debt_amount = user_loan_balance(storage, dola_user_id, dola_pool_id);
        let debt_value = user_loan_value(storage, oracle, dola_user_id, dola_pool_id);
        emit(UserDebtInfo {
            dola_pool_id,
            borrow_apy,
            supply_apy,
            debt_amount,
            debt_value
        })
    }

    public entry fun get_user_all_collateral(storgae: &mut Storage, dola_user_id: u64) {
        let dola_pool_ids = get_user_collaterals(storgae, dola_user_id);
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
        let borrow_rate = get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / RAY;
        let liquidity_rate = get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / RAY;
        let collateral_amount = user_collateral_balance(storage, dola_user_id, dola_pool_id);
        let collateral_value = user_collateral_value(storage, oracle, dola_user_id, dola_pool_id);
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
        let collateral_infos = vector::empty<UserCollateralInfo>();
        let collaterals = get_user_collaterals(storage, dola_user_id);
        let total_collateral_value = 0;

        let debt_infos = vector::empty<UserDebtInfo>();
        let loans = get_user_loans(storage, dola_user_id);
        let total_debt_value = 0;

        let total_supply_apy_value = 0;
        let total_borrow_apy_value = 0;

        let length = vector::length(&collaterals);
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let borrow_rate = get_borrow_rate(storage, *collateral);
            let borrow_apy = borrow_rate * 10000 / RAY;
            let liquidity_rate = get_liquidity_rate(storage, *collateral);
            let supply_apy = liquidity_rate * 10000 / RAY;
            let collateral_amount = user_collateral_balance(storage, dola_user_id, *collateral);
            let collateral_value = user_collateral_value(storage, oracle, dola_user_id, *collateral);
            total_supply_apy_value = total_supply_apy_value + ray_mul(collateral_value, liquidity_rate);
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
            let borrow_rate = get_borrow_rate(storage, *loan);
            let borrow_apy = borrow_rate * 10000 / RAY;
            let liquidity_rate = get_liquidity_rate(storage, *loan);
            let supply_apy = liquidity_rate * 10000 / RAY;
            let debt_amount = user_loan_balance(storage, dola_user_id, *loan);
            let debt_value = user_loan_value(storage, oracle, dola_user_id, *loan);
            total_borrow_apy_value = total_borrow_apy_value + ray_mul(debt_value, borrow_rate);
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
        let health_factor = user_health_factor(storage, oracle, dola_user_id);

        let user_total_supply_value = user_total_collateral_value(storage, oracle, dola_user_id);
        let user_total_debt_value = user_total_loan_value(storage, oracle, dola_user_id);

        let net_apy = 0;
        let total_supply_apy = 0;
        let total_borrow_apy = 0;
        let profit_state = true;

        if (user_total_supply_value > 0) {
            total_supply_apy = ray_div(total_supply_apy_value, user_total_supply_value);
            profit_state = true;
        };

        if (user_total_debt_value > 0) {
            total_borrow_apy = ray_div(total_borrow_apy_value, user_total_debt_value);
            profit_state = false;
        };

        if (user_total_supply_value > 0 && user_total_debt_value > 0) {
            if (total_supply_apy >= total_borrow_apy) {
                net_apy = total_supply_apy - total_borrow_apy;
                profit_state = true;
            } else {
                net_apy = total_borrow_apy - total_supply_apy;
                profit_state = false;
            }
        };

        net_apy = net_apy * 10000 / RAY;
        total_supply_apy = total_supply_apy * 10000 / RAY;
        total_borrow_apy = total_borrow_apy * 10000 / RAY;

        emit(UserLendingInfo {
            health_factor,
            profit_state,
            net_apy,
            total_supply_apy,
            total_borrow_apy,
            collateral_infos,
            total_collateral_value,
            debt_infos,
            total_debt_value
        })
    }

    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16
    ) {
        let pools = all_pool_liquidity(pool_manager_info, dola_pool_id);
        let borrow_coefficient = get_borrow_coefficient(storage, dola_pool_id);
        let collateral_coefficient = get_collateral_coefficient(storage, dola_pool_id);
        let borrow_rate = get_borrow_rate(storage, dola_pool_id);
        let borrow_apy = borrow_rate * 10000 / RAY;
        let liquidity_rate = get_liquidity_rate(storage, dola_pool_id);
        let supply_apy = liquidity_rate * 10000 / RAY;
        let debt = total_dtoken_supply(storage, dola_pool_id);
        let reserve = get_app_liquidity(pool_manager_info, dola_pool_id, get_app_id(storage));

        let utilization_rate = 0;
        if (debt > 0) {
            let utilization = calculate_utilization(storage, dola_pool_id, reserve);
            utilization_rate = utilization * 10000 / RAY;
        };

        emit(LendingReserveInfo {
            dola_pool_id,
            collateral_coefficient,
            borrow_coefficient,
            borrow_apy,
            supply_apy,
            reserve,
            debt,
            utilization_rate,
            pools
        })
    }

    public entry fun get_all_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage
    ) {
        let reserve_length = get_reserve_length(storage);
        let reserve_infos = vector::empty<LendingReserveInfo>();
        let i = 0;
        while (i < reserve_length) {
            let dola_pool_id = (i as u16);
            let pools = all_pool_liquidity(pool_manager_info, dola_pool_id);
            let borrow_coefficient = get_borrow_coefficient(storage, dola_pool_id);
            let collateral_coefficient = get_collateral_coefficient(storage, dola_pool_id);
            let borrow_rate = get_borrow_rate(storage, dola_pool_id);
            let borrow_apy = borrow_rate * 10000 / RAY;
            let liquidity_rate = get_liquidity_rate(storage, dola_pool_id);
            let supply_apy = liquidity_rate * 10000 / RAY;
            let debt = total_dtoken_supply(storage, dola_pool_id);
            let reserve = get_app_liquidity(pool_manager_info, dola_pool_id, get_app_id(storage));

            let utilization_rate = 0;
            if (debt > 0) {
                let utilization = calculate_utilization(storage, dola_pool_id, reserve);
                utilization_rate = utilization * 10000 / RAY;
            };

            let reserve_info = LendingReserveInfo {
                dola_pool_id,
                collateral_coefficient,
                borrow_coefficient,
                borrow_apy,
                supply_apy,
                reserve,
                debt,
                utilization_rate,
                pools
            };
            vector::push_back(&mut reserve_infos, reserve_info);
            i = i + 1;
        };
        emit(AllReserveInfo {
            reserve_infos
        })
    }

    public entry fun get_oracle_price(oracle: &mut PriceOracle, dola_pool_id: u16) {
        let (price, decimal) = get_token_price(oracle, dola_pool_id);
        emit(TokenPrice {
            dola_pool_id,
            price,
            decimal
        })
    }

    public entry fun get_all_oracle_price(storage: &mut Storage, oracle: &mut PriceOracle) {
        let reserve_length = get_reserve_length(storage);
        let token_prices = vector::empty<TokenPrice>();
        let i = 0;
        while (i < reserve_length) {
            let dola_pool_id = (i as u16);
            let (price, decimal) = get_token_price(oracle, dola_pool_id);
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

    public entry fun get_user_allowed_borrow(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        dola_chain_id: u16,
        dola_user_id: u64,
        borrow_pool_id: u16
    ) {
        let borrow_token = into_bytes(get_pool_name_by_id(pool_manager_info, borrow_pool_id));
        if (is_collateral(storage, dola_user_id, borrow_pool_id)) {
            emit(UserAllowedBorrow {
                borrow_token,
                max_borrow_amount: 0,
                max_borrow_value: 0,
                borrow_amount: 0,
                borrow_value: 0,
                reason: option::some(string(b"Borrowed token is collateral"))
            });
            return
        };
        let health_collateral_value = user_health_collateral_value(storage, oracle, dola_user_id);
        let health_loan_value = user_health_loan_value(storage, oracle, dola_user_id);
        let borrow_coefficient = get_borrow_coefficient(storage, borrow_pool_id);
        let can_borrow_value = ray_div(health_collateral_value - health_loan_value, borrow_coefficient);
        let borrow_amount = calculate_amount(oracle, borrow_pool_id, can_borrow_value);
        let pool_address = find_pool_by_chain(pool_manager_info, borrow_pool_id, dola_chain_id);

        let pool_liquidity = 0;
        if (option::is_some(&pool_address)) {
            let pool_address = option::extract(&mut pool_address);
            pool_liquidity = pool_manager::get_pool_liquidity(pool_manager_info, pool_address);
        };
        let reserve = get_app_liquidity(pool_manager_info, borrow_pool_id, 0);

        let max_borrow_amount = min(borrow_amount, (reserve as u64));
        borrow_amount = min(borrow_amount, pool_liquidity);
        let max_borrow_value = calculate_value(oracle, borrow_pool_id, max_borrow_amount);
        let borrow_value = calculate_value(oracle, borrow_pool_id, borrow_amount);
        emit(UserAllowedBorrow {
            borrow_token,
            max_borrow_amount,
            max_borrow_value,
            borrow_amount,
            borrow_value,
            reason: option::none()
        })
    }
}
