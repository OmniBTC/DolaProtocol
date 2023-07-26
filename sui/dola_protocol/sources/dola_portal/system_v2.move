module dola_protocol::system_portal_v2 {
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::event;
    use sui::sui::SUI;
    use sui::tx_context;
    use sui::tx_context::TxContext;

    use dola_protocol::dola_address;
    use dola_protocol::genesis;
    use dola_protocol::genesis::GovernanceGenesis;
    use dola_protocol::system_codec;
    use dola_protocol::wormhole_adapter_pool;
    use dola_protocol::wormhole_adapter_pool::PoolState;
    use wormhole::state::State as WormholeState;

    /// App ID

    const SYSTEM_APP_ID: u16 = 0;

    /// === Events ===

    // Since the protocol can be directly connected on sui,
    // this is a special event for the sui chain.
    struct SystemPortalEvent has drop, copy {
        nonce: u64,
        sender: address,
        user_chain_id: u16,
        user_address: vector<u8>,
        call_type: u8
    }

    /// === Entry Functions ===

    entry fun binding(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_chain_id: u16,
        binded_address: vector<u8>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let bind_dola_address = dola_address::create_dola_address(dola_chain_id, binded_address);
        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = system_codec::encode_bind_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            bind_dola_address,
            system_codec::get_binding_type()
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
            SYSTEM_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            SYSTEM_APP_ID,
            system_codec::get_binding_type()
        );

        event::emit(
            SystemPortalEvent {
                nonce,
                sender: tx_context::sender(ctx),
                user_chain_id: dola_chain_id,
                user_address: binded_address,
                call_type: system_codec::get_binding_type()
            }
        )
    }

    entry fun unbinding(
        genesis: &GovernanceGenesis,
        pool_state: &mut PoolState,
        wormhole_state: &mut WormholeState,
        dola_chain_id: u16,
        unbinded_address: vector<u8>,
        bridge_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        genesis::check_latest_version(genesis);
        let unbind_dola_address = dola_address::create_dola_address(dola_chain_id, unbinded_address);
        let nonce = wormhole_adapter_pool::get_nonce(pool_state);

        let app_payload = system_codec::encode_bind_payload(
            dola_address::get_native_dola_chain_id(),
            nonce,
            unbind_dola_address,
            system_codec::get_unbinding_type()
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
            SYSTEM_APP_ID,
            app_payload,
            clock,
            ctx
        );

        wormhole_adapter_pool::emit_relay_event(
            sequence,
            nonce,
            relay_fee_amount,
            SYSTEM_APP_ID,
            system_codec::get_unbinding_type()
        );

        event::emit(
            SystemPortalEvent {
                nonce,
                sender: tx_context::sender(ctx),
                user_chain_id: dola_chain_id,
                user_address: unbinded_address,
                call_type: system_codec::get_unbinding_type()
            }
        )
    }
}
