import json
from pathlib import Path

import dola_ethereum_sdk
from dola_ethereum_sdk.load import booltest_consumer_package

import sui_brownie
from sui_brownie import Argument, U16
from dola_sui_sdk.load import booltest_anchor_package
from dola_sui_sdk import set_dola_project_path, sui_project

def test_eth_consumer():
    network = "bevm-test"
    dola_ethereum_sdk.set_dola_project_path(Path(__file__).parent.parent.parent)
    dola_ethereum_sdk.set_ethereum_network(network)
    mb = booltest_consumer_package("0x955034955264BCc103108DbfC2d0768C367b3a63")

    # sui-testnet
    dst_chainid = 1918346523
    fee = mb.calculateFee(dst_chainid, len(b"hello"))

    print(fee)

def test_sui_anchor():
    set_dola_project_path(
        Path(__file__).parent.parent.parent,
        network="sui-testnet"
    )

    mb = booltest_anchor_package("0x65da07243a0579ae918f74aad5fbd1fedf13006163cbf5564fbaccbd5ec5741c")

    bool_global = "0x85c4c4f30a3cb2b982950b35bd1e189a3f47504341c12430dcf6bca120d3be3d"
    # public fun calc_bool_fee(
    #     global: &GlobalState,
    #     chain_id: u32,
    #     payload_length: u64,
    #     extra_feed_length: u64
    # ): u64
    dst_chainid = 1502
    fee_result = mb.bridge.calc_bool_fee.inspect(
        bool_global,
        dst_chainid,
        0,
        0
    )

    fee = int.from_bytes(fee_result["results"][0]["returnValues"][0][0], "little")

    print(fee)

def test_sui_get_object():
    client = sui_brownie.SuiClient("https://fullnode.testnet.sui.io", timeout=60)

    r = client.sui_getNormalizedMoveModulesByPackage(
        "0x65da07243a0579ae918f74aad5fbd1fedf13006163cbf5564fbaccbd5ec5741c"
    )

    print(json.dumps(r, indent=2))


def sui_send_msg(msg: bytes):
    set_dola_project_path(
        Path(__file__).parent.parent.parent,
        network="sui-testnet"
    )

    mb = booltest_anchor_package("0x65da07243a0579ae918f74aad5fbd1fedf13006163cbf5564fbaccbd5ec5741c")

    dst_chainid = 1502
    anchor_cap = "0x0c8fe8bca1d62389b34355b36559a0c5ef7afc677397ca425f5a9d9b3166674d"
    global_state = "0x85c4c4f30a3cb2b982950b35bd1e189a3f47504341c12430dcf6bca120d3be3d"

    fee_result = mb.bridge.calc_bool_fee.inspect(
        global_state,
        dst_chainid,
        len(msg),
        0
    )

    fee = int.from_bytes(fee_result["results"][0]["returnValues"][0][0], "little")
    print(f"fee={fee}\n")

    # public entry fun send_msg(
    #   dst_chain_id: u32,
    #   msg: vector<u8>,
    #   fee: Coin<SUI>,
    #   anchor_cap: &AnchorCap,
    #   state: &mut GlobalState,
    #   ctx: &mut TxContext
    # )
    result = sui_project.batch_transaction(
        actual_params=[dst_chainid, list(msg), fee, anchor_cap, global_state],
        transactions=[
            [
                mb.bridge.send_msg,
                [
                    Argument("Input", U16(0)),
                    Argument("Input", U16(1)),
                    Argument("Input", U16(2)),
                    Argument("Input", U16(3)),
                    Argument("Input", U16(4)),
                ],
                [],
            ]
        ],
    )

    print(json.dumps(result, indent=2))


def eth_send_msg(msg: bytes):
    network = "bevm-test"
    dola_ethereum_sdk.set_dola_project_path(Path(__file__).parent.parent.parent)
    dola_ethereum_sdk.set_ethereum_network(network)

    mb = booltest_consumer_package("0x955034955264BCc103108DbfC2d0768C367b3a63")
    account = dola_ethereum_sdk.get_account()

    # sui-testnet
    dst_chainid = 1918346523
    fee = mb.calculateFee(dst_chainid, len(msg))

    gas = mb.send_msg.estimate_gas(
        dst_chainid, msg, {"from": account, "gas_price": 100000000, "value": fee}
    )
    print(f"fee={fee}, gas={gas}")

    result = mb.send_msg(
        dst_chainid, msg, {"from": account, "gas_price": 100000000, "value": fee}
    )
    print(f"txid={result.txid}")

if __name__ == '__main__':
    test_eth_consumer()
    # test_sui_anchor()
    # test_sui_get_object()
    # sui_send_msg(b"good")
    # eth_send_msg(b"very good")