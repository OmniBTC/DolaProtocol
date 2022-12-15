module wormhole_bridge::bridge_pool {
    use omnipool::pool::{Self, PoolCap, deposit_and_withdraw};
    use wormhole::emitter::EmitterCapability;
    use wormhole::external_address::{Self, ExternalAddress};
    use wormhole::wormhole;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use wormhole::set::Set;
    use aptos_std::table::Table;
    use serde::u16::U16;
    use wormhole::set;
    use aptos_std::table;
    use aptos_framework::coin::Coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use dola_types::types::DolaAddress;

    const EMUST_DEPLOYER: u64 = 0;

    const EMUST_ADMIN: u64 = 1;

    const ENOT_INIT: u64 = 2;

    const SEED: vector<u8> = b"Dola wormhole_bridge";

    struct PoolState has key, store {
        resource_cap: SignerCapability,
        pool_cap: PoolCap,
        sender: EmitterCapability,
        consumed_vaas: Set<vector<u8>>,
        registered_emitters: Table<U16, ExternalAddress>,
        // todo! Deleta after wormhole running
        cache_vaas: Table<u64, vector<u8>>,
        nonce: u64
    }

    struct VaaEvent has key, copy, drop {
        vaa: vector<u8>
    }

    struct VaaReciveWithdrawEvent has key, copy, drop {
        pool_address: DolaAddress,
        user: DolaAddress,
        amount: u64,
    }

    public fun ensure_admin(sender: &signer): bool {
        signer::address_of(sender) == @wormhole_bridge
    }

    public fun ensure_init(): bool {
        exists<PoolState>(get_resource_address())
    }

    public fun get_resource_address(): address {
        account::create_resource_address(&@wormhole_bridge, SEED)
    }

    public entry fun initialize_wormhole(sender: &signer) {
        assert!(ensure_admin(sender), EMUST_ADMIN);
        assert!(!ensure_init(), ENOT_INIT);

        let wormhole_emitter = wormhole::register_emitter();
        let (resource_signer, resource_cap) = account::create_resource_account(sender, SEED);
        move_to(&resource_signer, PoolState {
            resource_cap,
            pool_cap: pool::register_cap(sender),
            sender: wormhole_emitter,
            consumed_vaas: set::new<vector<u8>>(),
            registered_emitters: table::new(),
            cache_vaas: table::new(),
            nonce: 0
        });
    }

    public entry fun register_remote_bridge(
        sender: &signer,
        emitter_chain_id: U16,
        emitter_address: vector<u8>,
    ) acquires PoolState {
        // todo! change into govern permission
        assert!(ensure_admin(sender), EMUST_ADMIN);

        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        // todo! consider remote register
        table::add(
            &mut pool_state.registered_emitters,
            emitter_chain_id,
            external_address::from_bytes(emitter_address)
        );
    }

    public fun send_deposit<CoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        deposit_coin: Coin<CoinType>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = pool::deposit_to<CoinType>(
            sender,
            deposit_coin,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_withdraw<CoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = pool::withdraw_to<CoinType>(
            sender,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public fun send_deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
        sender: &signer,
        wormhole_message_fee: Coin<AptosCoin>,
        deposit_coin: Coin<DepositCoinType>,
        app_id: U16,
        app_payload: vector<u8>,
    ) acquires PoolState {
        let msg = deposit_and_withdraw<DepositCoinType, WithdrawCoinType>(
            sender,
            deposit_coin,
            app_id,
            app_payload,
        );
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        wormhole::publish_message(&mut pool_state.sender, 0, msg, wormhole_message_fee);
        pool_state.nonce = pool_state.nonce + 1;
        table::add(&mut pool_state.cache_vaas, pool_state.nonce, msg);
    }

    public entry fun receive_withdraw<CoinType>(
        vaa: vector<u8>,
    ) acquires PoolState {
        // todo: wait for wormhole to go live on the sui testnet and use payload directly for now
        // let vaa = parse_verify_and_replay_protect(
        //     wormhole_state,
        //     &pool_state.registered_emitters,
        //     &mut pool_state.consumed_vaas,
        //     vaa,
        //     ctx
        // );
        // let (_pool_address, user, amount, token_name) =
        //     pool::decode_receive_withdraw_payload(myvaa::get_payload(&vaa));
        let (pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());

        pool::inner_withdraw<CoinType>(&pool_state.pool_cap, user, amount, pool_address);
        // myvaa::destroy(vaa);
    }

    public entry fun read_vaa(sender: &signer, index: u64) acquires PoolState {
        let pool_state = borrow_global_mut<PoolState>(get_resource_address());
        if (index == 0) {
            index = pool_state.nonce;
        };
        move_to(sender, VaaEvent {
            vaa: *table::borrow(&pool_state.cache_vaas, index)
        });
    }

    public entry fun decode_receive_withdraw_payload(sender: &signer, vaa: vector<u8>) {
        let (pool_address, user, amount) =
            pool::decode_receive_withdraw_payload(vaa);
        move_to(sender, VaaReciveWithdrawEvent {
            pool_address,
            user,
            amount
        })
    }
}
