module protocol_core::message_types {

    const APPID: u16 = 0;

    const BINDING: u8 = 5;

    const UNBINDING: u8 = 6;

    public fun app_id(): u16 {
        APPID
    }

    public fun binding_type_id(): u8 {
        BINDING
    }

    public fun unbinding_type_id(): u8 {
        UNBINDING
    }
}
