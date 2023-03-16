// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
module test_coins::coins {

    use aptos_framework::account;
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;

    const SEED: vector<u8> = b"TestCoin";

    const EMUST_DEPLOYER: u64 = 0;

    const ENOT_INITIALIZE: u64 = 1;

    const ONE_COIN: u64 = 100000000;

    ////////////////////////////////////
    struct USDT has drop {}

    struct XBTC has drop {}

    struct BTC has drop {}

    struct ETH has drop {}

    struct BNB has drop {}

    struct WBTC has drop {}

    struct USDC has drop {}

    struct DAI has drop {}

    struct MATIC has drop {}

    ////////////////////////////////////

    struct SignerCapability has key {
        signer_cap: account::SignerCapability,
        deployer: address,
    }

    fun get_resource_address(): address {
        account::create_resource_address(&@test_coins, SEED)
    }

    fun get_resouce_signer(): signer acquires SignerCapability {
        assert!(exists<SignerCapability>(get_resource_address()), ENOT_INITIALIZE);
        let resource = get_resource_address();
        let deploying_cap = borrow_global<SignerCapability>(resource);
        account::create_signer_with_capability(&deploying_cap.signer_cap)
    }

    fun inner_initialize<CoinType>(account: &signer, name: vector<u8>) acquires SignerCapability {
        if (!coin::is_coin_initialized<CoinType>()) {
            managed_coin::initialize<CoinType>(account, name, name, 8, true);
            if (!coin::is_account_registered<CoinType>(get_resource_address())) {
                coin::register<CoinType>(&get_resouce_signer());
            };
            managed_coin::mint<CoinType>(account, get_resource_address(), 1000000000000000000);
        };
    }

    public entry fun initialize(account: &signer) acquires SignerCapability {
        assert!(signer::address_of(account) == @test_coins, EMUST_DEPLOYER);
        let resource = get_resource_address();
        let resource_signer;
        if (!exists<SignerCapability>(resource)) {
            let signer_cap;
            (resource_signer, signer_cap) = account::create_resource_account(account, SEED);
            move_to(&resource_signer, SignerCapability { signer_cap, deployer: @test_coins });
        };

        inner_initialize<USDT>(account, b"USDT");
        inner_initialize<XBTC>(account, b"XBTC");
        inner_initialize<BTC>(account, b"BTC");
        inner_initialize<ETH>(account, b"ETH");
        inner_initialize<BNB>(account, b"BNB");
        inner_initialize<WBTC>(account, b"WBTC");
        inner_initialize<USDC>(account, b"USDC");
        inner_initialize<DAI>(account, b"DAI");
        inner_initialize<MATIC>(account, b"MATIC");
    }

    public entry fun claim<T>(
        account: &signer
    ) acquires SignerCapability {
        let resource_signer = get_resouce_signer();
        let addr = signer::address_of(account);

        if (!coin::is_account_registered<T>(addr)) {
            coin::register<T>(account);
        };
        coin::transfer<T>(&resource_signer, addr, ONE_COIN);
    }
}
