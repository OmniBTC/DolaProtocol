/// Handling messages from the bridge
module omnicore::message_core {

    use std::vector;

    /// process payload and return response
    public fun process_payload(_: vector<u8>): vector<u8> {
        // todo:
        vector::empty<u8>()
    }
}
