/// Unified external call interface to get data
/// by simulating calls to trigger events.
module external_interfaces::interfaces {

    use std::vector;

    use lending::logic::{user_loan_balance, user_loan_value, user_collateral_balance, user_collateral_value, total_dtoken_supply};
    use lending::rates::calculate_utilization;
    use lending::storage::{Storage, get_user_collaterals, get_user_loans, get_borrow_rate, get_liquidity_rate, get_app_id};
    use oracle::oracle::PriceOracle;
    use pool_manager::pool_manager::{token_liquidity, PoolManagerInfo, get_app_liquidity};
    use sui::event::emit;

    const RAY: u64 = 100000000;

    struct PoolInfo has store, drop {}

    struct TokenLiquidityInfo has copy, drop {
        token_name: vector<u8>,
        token_liquidity: u64,
    }

    struct AppLiquidityInfo has copy, drop {
        app_id: u16,
        token_name: vector<u8>,
        token_liquidity: u128,
    }

    struct LendingReserveInfo has copy, drop {
        token_name: vector<u8>,
        borrow_apy: u64,
        supply_apy: u64,
        reserve: u128,
        debt: u128,
        utilization_rate: u64
    }

    struct LendingUserInfo has copy, drop {
        healeth_factor: u64,
        collateral: UserCollateralInfo,
        debt: UserDebtInfo,
    }

    struct UserLendingInfo has copy, drop {
        collateral_infos: vector<UserCollateralInfo>,
        total_collateral_value: u64,
        debt_infos: vector<UserDebtInfo>,
        total_debt_value: u64
    }

    struct UserCollateralInfo has copy, drop {
        token_name: vector<u8>,
        collateral_amount: u64,
        collateral_value: u64
    }

    struct UserDebtInfo has copy, drop {
        token_name: vector<u8>,
        debt_amount: u64,
        debt_value: u64,
    }

    public entry fun get_dora_token_liquidity(pool_manager_info: &mut PoolManagerInfo, token_name: vector<u8>) {
        let token_liquidity = token_liquidity(pool_manager_info, token_name);
        emit(TokenLiquidityInfo {
            token_name,
            token_liquidity
        })
    }

    public entry fun get_app_token_liquidity(
        pool_manager_info: &mut PoolManagerInfo,
        app_id: u16,
        token_name: vector<u8>
    ) {
        let token_liquidity = get_app_liquidity(pool_manager_info, token_name, app_id);
        emit(AppLiquidityInfo {
            app_id,
            token_name,
            token_liquidity
        })
    }

    public entry fun get_user_token_debt(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>
    ) {
        let debt_amount = user_loan_balance(storage, user_address, token_name);
        let debt_value = user_loan_value(storage, oracle, user_address, token_name);
        emit(UserDebtInfo {
            token_name,
            debt_amount,
            debt_value
        })
    }

    public entry fun get_user_collateral(
        storage: &mut Storage,
        oracle: &mut PriceOracle,
        user_address: vector<u8>,
        token_name: vector<u8>
    ) {
        let collateral_amount = user_collateral_balance(storage, user_address, token_name);
        let collateral_value = user_collateral_value(storage, oracle, user_address, token_name);
        emit(UserCollateralInfo {
            token_name,
            collateral_amount,
            collateral_value
        })
    }

    public entry fun get_user_lending_info(storage: &mut Storage, oracle: &mut PriceOracle, user_address: vector<u8>) {
        let collateral_infos = vector::empty<UserCollateralInfo>();
        let collaterals = get_user_collaterals(storage, user_address);
        let total_collateral_value = 0;
        let debt_infos = vector::empty<UserDebtInfo>();
        let loans = get_user_loans(storage, user_address);
        let total_debt_value = 0;

        let length = vector::length(&collaterals);
        let i = 0;
        while (i < length) {
            let collateral = vector::borrow(&collaterals, i);
            let collateral_amount = user_collateral_balance(storage, user_address, *collateral);
            let collateral_value = user_collateral_value(storage, oracle, user_address, *collateral);
            vector::push_back(&mut collateral_infos, UserCollateralInfo {
                token_name: *collateral,
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
            let debt_amount = user_loan_balance(storage, user_address, *loan);
            let debt_value = user_loan_value(storage, oracle, user_address, *loan);
            vector::push_back(&mut debt_infos, UserDebtInfo {
                token_name: *loan,
                debt_amount,
                debt_value
            });
            total_debt_value = total_debt_value + debt_value;
            i = i + 1;
        };

        emit(UserLendingInfo {
            collateral_infos,
            total_collateral_value,
            debt_infos,
            total_debt_value
        })
    }

    public entry fun get_reserve_info(
        pool_manager_info: &mut PoolManagerInfo,
        storage: &mut Storage,
        token_name: vector<u8>
    ) {
        let borrow_rate = get_borrow_rate(storage, token_name);
        let borrow_apy = borrow_rate * 10000 / RAY;
        let liquidity_rate = get_liquidity_rate(storage, token_name);
        let supply_apy = liquidity_rate * 10000 / RAY;
        let debt = total_dtoken_supply(storage, token_name);
        let reserve = get_app_liquidity(pool_manager_info, token_name, get_app_id(storage));
        let utilization = calculate_utilization(storage, token_name, reserve);
        let utilization_rate = utilization * 10000 / RAY;
        emit(LendingReserveInfo {
            token_name,
            borrow_apy,
            supply_apy,
            reserve,
            debt,
            utilization_rate
        })
    }
}
