
// [REQUIRED]
// you MUST have module "consumer_receivable" where deliver will send cross_chain transaction here.
module message_bridge::consumer_receivable {
    use sui::tx_context::TxContext;
    use boolamt::anchor::{GlobalState, AnchorCap};
    use boolamt::consumer;

    use message_bridge::bridge::emit_receive;

    // module consumer MUST have this function signature which finally call [anchor::receive_message].
    // To submit cross chain messages, we require this entry which is called by bool monitor.
    public entry fun receive_message(
        message_raw: vector<u8>,
        signature: vector<u8>,
        anchor_cap: &AnchorCap,
        state: &mut GlobalState,
        _ctx: &mut TxContext,
    ) {
        // all check here.
        let (payload, _) = consumer::receive_message(
            message_raw,
            signature,
            anchor_cap,
            state
        );

        emit_receive(payload);
    }
}