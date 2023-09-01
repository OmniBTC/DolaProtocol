BoolTypes = {
    # "runtime_id": 167,
    "types": {
        "CommitteeId": "u32",
        "SubmitTransaction": {
            "type": "struct",
            "type_mapping": [
                ["cid", "CommitteeId"],
                ["u32", "u32"],
                ["u8", "u8"],
                ["Hash", "H256"],
            ],
        },
        "AuthorityId": "[u8; 32]",
        "Address": "MultiAddress",
        "AccountId": "H160",
        "ExtrinsicSignature": "EthereumSignature",
        "LookupSource": "MultiAddress",
        "DIdentity": {
            "type": "struct",
            "type_mapping": [["version", "u16"], ["pk", "Vec<u8>"]],
        },
        "Device": {
            "type": "struct",
            "type_mapping": [
                ["owner", "AccountId"],
                ["did", "DIdentity"],
                ["report", "Vec<u8>"],
                ["state", "DeviceState"],
            ],
        },
        "DeviceState": {
            "type": "enum",
            "value_list": [
                "Unmount",
                "Stop",
                "Standby",
                "Offline",
                "Serving",
                "TryExit",
            ],
        },
        "StakingState": {
            "type": "struct",
            "type_mapping": [
                ["user", "AccountId"],
                ["locked", "Balance"],
                ["start_time", "u64"],
            ],
        },
        "OnChainEvent": {
            "type": "enum",
            "type_mapping": [["OnChainPayload", "OnChainPayload"]],
        },
        "OnChainPayload": {
            "type": "struct",
            "type_mapping": [
                ["did", "DIdentity"],
                ["proof", "Vec<u8>"],
                ["timestamp", "u64"],
                ["session", "BlockNumber"],
                ["signature", "Vec<u8>"],
                ["enclave", "Vec<u8>"],
            ],
        },
        "ProviderId": "u32",
        "ProviderInfo": {
            "type": "struct",
            "type_mapping": [
                ["pid", "ProviderId"],
                ["owner", "AccountId"],
                ["devices", "Vec<DIdentity>"],
                ["cap_pledge", "Balance"],
                ["total_pledge", "Balance"],
                ["score", "u128"],
                ["rewards", "Balance"],
                ["punishment", "Balance"],
                ["staking_user_num", "u8"],
                ["status", "ProviderState"],
            ],
        },
        "ProviderState": {"type": "enum", "value_list": ["Stop", "Working"]},
        "StakeInfo": {
            "type": "struct",
            "type_mapping": [
                ["locked", "Balance"],
                ["available_rewards", "Vec<(ProviderId, DIdentity, Balance)>"],
            ],
        },
        "MessageOrigin": {
            "type": "enum",
            "type_mapping": [
                ["Pallet", "Vec<u8>"],
                ["Did", "DIdentity"],
                ["AccountId", "AccountId"],
            ],
        },
        "Message": {
            "type": "struct",
            "type_mapping": [
                ["sender", "MessageOrigin"],
                ["destination", "Vec<u8>"],
                ["payload", "Vec<u8>"],
            ],
        },
        "CommitteeState": {
            "type": "enum",
            "value_list": [
                "Creating",
                "Initializing",
                "Stop",
                "Working",
                "CreateFinished",
            ],
        },
        "ChannelState": {"type": "enum", "value_list": ["Stop", "Working"]},
        "HandleConnection": {
            "type": "enum",
            "type_mapping": [
                ["Cid", "CommitteeId"],
                ["CidWithAnchor", "(CommitteeId, u32, Vec<u8>)"],
                ["CommitteeParam", "(u16, u16, CryptoType, u8)"],
            ],
        },
        "CryptoType": {
            "type": "enum",
            "value_list": ["Ecdsa", "Bls", "Schnorr", "Eddsa"],
        },
        "Source": {"type": "enum", "value_list": ["Mining", "Serving"]},
        "Channel": {
            "type": "struct",
            "type_mapping": [
                ["channel_id", "u32"],
                ["creator", "AccountId"],
                ["info", "Vec<u8>"],
                ["cids", "Vec<(CommitteeId, u32)>"],
                ["state", "ChannelState"],
            ],
        },
        "Parameters": {"type": "struct", "type_mapping": [["t", "u16"], ["n", "u16"]]},
        "ExitParameters": {
            "type": "enum",
            "type_mapping": [
                ["Normal", "Vec<ProviderId>"],
                ["Force", "(CommitteeId, u8, Vec<u8>, Vec<u8>)"],
            ],
        },
        "OnChainPayloadVRF": {
            "type": "struct",
            "type_mapping": [
                ["cid", "CommitteeId"],
                ["epoch", "u32"],
                ["pk", "Vec<u8>"],
                ["proof", "Vec<u8>"],
                ["fork_id", "u8"],
            ],
        },
        "Committee": {
            "type": "struct",
            "type_mapping": [
                ["cid", "CommitteeId"],
                ["creator", "AccountId"],
                ["epoch", "u32"],
                ["parameters", "Parameters"],
                ["pubkey", "Vec<u8>"],
                ["state", "CommitteeState"],
                ["crypto", "CryptoType"],
                ["fork", "u8"],
                ["channel_id", "u32"],
                ["chain_id", "u32"],
                ["anchor", "Vec<u8>"],
                ["times", "(BlockNumber, BlockNumber)"],
            ],
        },
        "TxSource": {
            "type": "struct",
            "type_mapping": [
                ["chain_type", "u16"],
                ["uid", "Vec<u8>"],
                ["from", "Vec<u8>"],
                ["to", "Vec<u8>"],
                ["amount", "U256"],
            ],
        },
        "BlockNumber": "u32",
        "TxMessage": {
            "type": "struct",
            "type_mapping": [
                ["cid", "u32"],
                ["epoch", "u32"],
                ["sid", "u64"],
                ["msg", "Vec<u8>"],
                ["txsource", "TxSource"],
                ["signature", "Vec<u8>"],
                ["time_limit", "BlockNumber"],
                ["choose_index", "Vec<u16>"],
                ["status", "TxStatus"],
            ],
        },
        "EpochChange": {
            "type": "struct",
            "type_mapping": [
                ["msg", "Vec<u8>"],
                ["signature", "Vec<u8>"],
                ["pubkey", "Vec<u8>"],
            ],
        },
        "TxStatus": {
            "type": "enum",
            "value_list": ["Unsigned", "Finished", "Abnormal", "Drop"],
        },
        "BtcTxTunnel": {"type": "enum", "value_list": ["Empty", "Verifying", "Open"]},
        "ConfirmType": {"type": "enum", "value_list": ["SourceHash", "TxData"]},
        "DstChainType": {
            "type": "enum",
            "value_list": ["Raw", "Fil", "Bsc", "BtcMainnet", "Eth", "BtcTestnet"],
        },
        "SourceTXInfo": {
            "type": "struct",
            "type_mapping": [["src_chain_id", "u32"], ["src_hash", "Vec<u8>"]],
        },
        "RandomNumberParams": {
            "type": "struct",
            "type_mapping": [
                ["consumer_addr", "Vec<u8>"],
                ["bls_cid_and_sig", "(u32, Vec<u8>)"],
                ["ecdsa_cid_and_sig", "(u32, Vec<u8>)"],
                ["number", "Vec<u8>"],
            ],
        },
    },
    "versioning": [],
}

ChainType = {
    0: "Raw",
    1: "Fil",
    2: "Bsc",
    3: "Btc",
    4: "Eth",
    5: "Solana",
    6: "Aptos",
    7: "Starknet",
    8: "Sui",
    9: "Substrate",
}