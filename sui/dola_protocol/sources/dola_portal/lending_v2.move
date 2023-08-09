module dola_protocol::lending_portal_v2 {
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::event;
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};

    use dola_protocol::dola_address::Self;
    use dola_protocol::dola_pool::Pool;
    use dola_protocol::genesis::{Self, GovernanceGenesis};
    use dola_protocol::lending_codec;
    use dola_protocol::merge_coins;
    use dola_protocol::wormhole_adapter_pool::{Self, PoolState};
    use wormhole::state::State as WormholeState;
    use dola_protocol::lending_core_storage::Storage;
    use dola_protocol::boost::RewardPool;
    use dola_protocol::user_manager;
    use dola_protocol::user_manager::UserManagerInfo;
    use dola_protocol::boost;
    use sui::transfer;

    /// Errors
    const EAMOUNT_NOT_ZERO: u64 = 0;

    /// App ID
    const LENDING_APP_ID: u16 = 1;

    /// Events

    /// Lending portal event
    struct LendingPortalEvent has drop, copy {
        nonce: u64,
        sender: address,
        dola_pool_address: vector<u8>,
        source_chain_id: u16,
        dst_chain_id: u16,
        receiver: vector<u8>,
        amount: u64,
        call_type: u8
    }

    /// === Entry Functions ===

    entry fun as_collateral(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_pool_ids: vector<u16>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let sender = tx_context::sender(ctx);
        let dst_pool = dola_address::convert_address_to_dola(sender);
        let app_payload = lending_codec::encode_manage_collateral_payload(
            dola_pool_ids,
            lending_codec::get_as_colleteral_type()
        );

        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_message(
            pool_state,
            wormhole_state,
            wormhole_fee,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_as_colleteral_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender,
                dola_pool_address: dola_address::get_dola_address(&dst_pool),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dola_address::get_native_dola_chain_id(),
                receiver: dola_address::get_dola_address(&dst_pool),
                amount: 0,
                call_type: lending_codec::get_as_colleteral_type()
            }
        )
    }

    entry fun cancel_as_collateral(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_pool_ids: vector<u16>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let sender = tx_context::sender(ctx);
        let dst_pool = dola_address::convert_address_to_dola(sender);
        let app_payload = lending_codec::encode_manage_collateral_payload(
            dola_pool_ids,
            lending_codec::get_cancel_as_colleteral_type()
        );

        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_message(
            pool_state,
            wormhole_state,
            wormhole_fee,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_cancel_as_colleteral_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender,
                dola_pool_address: dola_address::get_dola_address(&dst_pool),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dola_address::get_native_dola_chain_id(),
                receiver: dola_address::get_dola_address(&dst_pool),
                amount: 0,
                call_type: lending_codec::get_cancel_as_colleteral_type()
            }
        )
    }

    entry fun supply<CoinType>(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        pool: &mut Pool<CoinType>,
        deposit_coins: vector<Coin<CoinType>>,
        deposit_amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        assert!(deposit_amount > 0, EAMOUNT_NOT_ZERO);
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let deposit_coin = merge_coins::merge_coin<CoinType>(deposit_coins, deposit_amount, ctx);

        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = lending_codec::encode_deposit_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            user_address,
            lending_codec::get_supply_type()
        );

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_deposit(
            pool_state,
            wormhole_state,
            wormhole_fee,
            pool,
            deposit_coin,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_supply_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender: tx_context::sender(ctx),
                dola_pool_address: dola_address::get_dola_address(&pool_address),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dola_address::get_native_dola_chain_id(),
                receiver: dola_address::get_dola_address(&user_address),
                amount: deposit_amount,
                call_type: lending_codec::get_supply_type()
            }
        )
    }

    entry fun withdraw(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain_id: u16,
        pool: vector<u8>,
        receiver: vector<u8>,
        amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let user_address = dola_address::create_dola_address(dst_chain_id, receiver);
        let pool_address = dola_address::create_dola_address(dst_chain_id, pool);

        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = lending_codec::encode_withdraw_payload(
            dst_chain_id,
            nonce,
            amount,
            pool_address,
            user_address,
            lending_codec::get_withdraw_type()
        );

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_message(
            pool_state,
            wormhole_state,
            wormhole_fee,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_withdraw_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender: tx_context::sender(ctx),
                dola_pool_address: pool,
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id,
                receiver,
                amount,
                call_type: lending_codec::get_withdraw_type()
            }
        )
    }


    /// Since the protocol is deployed on sui, borrow on sui can be skipped across the chain
    entry fun borrow(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dst_chain_id: u16,
        pool: vector<u8>,
        receiver: vector<u8>,
        amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let user_address = dola_address::create_dola_address(dst_chain_id, receiver);
        let pool_address = dola_address::create_dola_address(dst_chain_id, pool);

        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = lending_codec::encode_withdraw_payload(
            dst_chain_id,
            nonce,
            amount,
            pool_address,
            user_address,
            lending_codec::get_borrow_type()
        );

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_message(
            pool_state,
            wormhole_state,
            wormhole_fee,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_borrow_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender: tx_context::sender(ctx),
                dola_pool_address: pool,
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id,
                receiver,
                amount,
                call_type: lending_codec::get_borrow_type()
            }
        )
    }

    public entry fun repay<CoinType>(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        pool: &mut Pool<CoinType>,
        repay_coins: vector<Coin<CoinType>>,
        repay_amount: u64,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        assert!(repay_amount > 0, EAMOUNT_NOT_ZERO);
        let user_address = dola_address::convert_address_to_dola(tx_context::sender(ctx));
        let pool_address = dola_address::convert_pool_to_dola<CoinType>();
        let deposit_coin = merge_coins::merge_coin<CoinType>(repay_coins, repay_amount, ctx);

        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = lending_codec::encode_deposit_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            user_address,
            lending_codec::get_repay_type()
        );

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_deposit(
            pool_state,
            wormhole_state,
            wormhole_fee,
            pool,
            deposit_coin,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_repay_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender: tx_context::sender(ctx),
                dola_pool_address: dola_address::get_dola_address(&pool_address),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dola_address::get_native_dola_chain_id(),
                receiver: dola_address::get_dola_address(&user_address),
                amount: repay_amount,
                call_type: lending_codec::get_repay_type()
            }
        )
    }

    entry fun liquidate(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        // liquidators repay debts to obtain collateral
        repay_pool_id: u16,
        liquidate_user_id: u64,
        liquidate_pool_id: u16,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);

        let sender = tx_context::sender(ctx);
        let user_address = dola_address::convert_address_to_dola(sender);
        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = lending_codec::encode_liquidate_payload_v2(
            dola_address::get_native_dola_chain_id(),
            nonce,
            repay_pool_id,
            liquidate_user_id,
            liquidate_pool_id,
        );

        let (wormhole_fee, relay_fee_amount) = wormhole_adapter_pool::get_relay_fee_amount(
            wormhole_state,
            pool_state,
            nonce,
            bridge_fee,
            ctx
        );

        let sequence = wormhole_adapter_pool::send_message(
            pool_state,
            wormhole_state,
            wormhole_fee,
            LENDING_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            LENDING_APP_ID,
            lending_codec::get_liquidate_type()
        );

        event::emit(
            LendingPortalEvent {
                nonce,
                sender,
                dola_pool_address: dola_address::get_dola_address(&user_address),
                source_chain_id: dola_address::get_native_dola_chain_id(),
                dst_chain_id: dola_address::get_native_dola_chain_id(),
                receiver: dola_address::get_dola_address(&user_address),
                amount: 0,
                call_type: lending_codec::get_liquidate_type()
            }
        )
    }

    entry fun claim<X>(
        user_manager_info: &UserManagerInfo,
        storage: &mut Storage,
        dola_pool_id: u16,
        reward_action: u8,
        reward_pool_balance: &mut RewardPool<X>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let dola_user_id = user_manager::get_dola_user_id(
            user_manager_info,
            dola_address::convert_address_to_dola(tx_context::sender(ctx))
        );
        transfer::public_transfer(
            boost::claim(storage,
                dola_pool_id,
                dola_user_id,
                reward_action,
                reward_pool_balance,
                clock,
                ctx
            ),
            tx_context::sender(ctx)
        )
    }
}

