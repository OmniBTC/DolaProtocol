module message_bridge::bridge {
    use boolamt::fee_collector;
    use sui::tx_context::{sender, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;

    use boolamt::anchor::{GlobalState, get_fee_collector, AnchorCap};
    use boolamt::messenger;
    use boolamt::consumer;


    friend message_bridge::consumer_receivable;

    struct SentEvent has copy,drop {
        payload: vector<u8>
    }

    struct ReceiveEvent has copy,drop {
        payload: vector<u8>
    }

    public fun calc_bool_fee(
        global: &GlobalState,
        chain_id: u32,
        payload_length: u64,
        extra_feed_length: u64
    ): u64 {
        let fee_collector = get_fee_collector(global);
        let fee = fee_collector::cpt_fee(
            fee_collector,
            chain_id,
            payload_length,
            extra_feed_length
        );

        return fee
    }

    public entry fun send_msg(
        dst_chain_id: u32,
        msg: vector<u8>,
        fee: Coin<SUI>,
        anchor_cap: &AnchorCap,
        state: &mut GlobalState,
        ctx: &mut TxContext
    ){
        let remain_fee = consumer::send_message(
            dst_chain_id,
            messenger::pure_message(),
            // bn_extra_feed not used.
            std::vector::empty(),
            msg,
            fee,
            anchor_cap,
            state,
            ctx,
        );
        // return remaining fee
        if (coin::value(&remain_fee) == 0) {
            coin::destroy_zero(remain_fee);
        } else {
            transfer::public_transfer(remain_fee, sender(ctx));
        };


    }

    public(friend) fun emit_sent(
        payload: vector<u8>
    ) {
        sui::event::emit(
            SentEvent {
                payload
            }
        )
    }

    public(friend) fun emit_receive(
        payload: vector<u8>
    ) {
        sui::event::emit(
            ReceiveEvent {
                payload
            }
        )
    }
}