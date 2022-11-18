module lending::otoken {
    use std::vector;

    use serde::u256;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    const ENOT_ENOUGH_BALANCE: u64 = 0;

    const RAY: u128 = 1000000000000000000000000000;

    struct OTokenCap has key, store { id: UID }

    struct OTokenInfo has key {
        id: UID,
        // token_name => LendingPool
        otokens_supply: Table<vector<u8>, OTokenSupply>,
        // user_address => UserInfo
        users_info: Table<vector<u8>, UserInfo>
    }

    struct OTokenSupply has store {
        total_supply: u64
    }

    struct UserInfo has store {
        // tokens_name
        owned_otokens: vector<vector<u8>>,
        // token_name => UserLiquidity
        token_liquidity: Table<vector<u8>, UserLiquidity>
    }

    struct UserLiquidity has store {
        scaled_balance: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(OTokenInfo {
            id: object::new(ctx),
            otokens_supply: table::new(ctx),
            users_info: table::new(ctx)
        });
        transfer::transfer(OTokenCap {
            id: object::new(ctx)
        }, @lending)
    }

    public entry fun total_supply(otoken_info: &OTokenInfo, token_name: vector<u8>, index: u128): u64 {
        balance(table::borrow(&otoken_info.otokens_supply, token_name).total_supply, index)
    }

    public entry fun user_owned_tokens(otoken_info: &OTokenInfo, user_address: vector<u8>): vector<vector<u8>> {
        table::borrow(&otoken_info.users_info, user_address).owned_otokens
    }

    public entry fun user_balance(
        otoken_info: &OTokenInfo,
        user_address: vector<u8>,
        token_name: vector<u8>,
        index: u128
    ): u64 {
        let user_info = table::borrow(&otoken_info.users_info, user_address);
        let user_scaled_balance = table::borrow(&user_info.token_liquidity, token_name).scaled_balance;
        balance(user_scaled_balance, index)
    }

    public fun scaled_balance(balance: u64, index: u128): u64 {
        u256::as_u64(
            u256::div(
                u256::mul(u256::from_u64(balance), u256::from_u128(index)), u256::from_u128(RAY)
            )
        )
    }

    public fun balance(scaled_balance: u64, index: u128): u64 {
        u256::as_u64(
            u256::div(
                u256::mul(u256::from_u64(scaled_balance), u256::from_u128(RAY)), u256::from_u128(index)
            )
        )
    }

    public fun mint(
        _: & OTokenCap,
        otoken_info: &mut OTokenInfo,
        token_name: vector<u8>,
        user_address: vector<u8>,
        amount: u64,
        index: u128,
        ctx: &mut TxContext
    ) {
        let otokens_supply = &mut otoken_info.otokens_supply;
        let users_info = &mut otoken_info.users_info;
        let scaled_balance = scaled_balance(amount, index);
        if (!table::contains(otokens_supply, token_name)) {
            table::add(otokens_supply, token_name, OTokenSupply {
                total_supply: 0
            })
        };
        let otoken_supply = table::borrow_mut(otokens_supply, token_name);
        otoken_supply.total_supply = otoken_supply.total_supply + scaled_balance;

        if (!table::contains(users_info, user_address)) {
            table::add(users_info, user_address, UserInfo {
                owned_otokens: vector::empty(),
                token_liquidity: table::new(ctx)
            })
        };
        let user_info = table::borrow_mut(users_info, user_address);
        let owned_tokens = &mut user_info.owned_otokens;
        let token_liquidity = &mut user_info.token_liquidity;

        if (!vector::contains(owned_tokens, &token_name)) {
            vector::push_back(owned_tokens, token_name);
        };

        if (!table::contains(token_liquidity, token_name)) {
            table::add(token_liquidity, token_name, UserLiquidity {
                scaled_balance: 0
            });
        };
        let user_liquidity = table::borrow_mut(token_liquidity, token_name);
        user_liquidity.scaled_balance = user_liquidity.scaled_balance + scaled_balance;
    }

    public fun burn(
        _: & OTokenCap,
        otoken_info: &mut OTokenInfo,
        token_name: vector<u8>,
        user_address: vector<u8>,
        amount: u64,
        index: u128,
    ) {
        let otokens_supply = &mut otoken_info.otokens_supply;
        let users_info = &mut otoken_info.users_info;
        let scaled_balance = scaled_balance(amount, index);

        let otoken_supply = table::borrow_mut(otokens_supply, token_name);
        otoken_supply.total_supply = otoken_supply.total_supply - scaled_balance;

        let user_info = table::borrow_mut(users_info, user_address);
        let token_liquidity = &mut user_info.token_liquidity;

        let user_liquidity = table::borrow_mut(token_liquidity, token_name);
        assert!(user_liquidity.scaled_balance >= scaled_balance, ENOT_ENOUGH_BALANCE);
        user_liquidity.scaled_balance = user_liquidity.scaled_balance - scaled_balance;
    }
}
