# @Time    : 2022/12/7 17:21
# @Author  : WeiDai
# @FileName: relayer.py
import functools
import hashlib
import json
import logging
import time
import traceback
from collections import OrderedDict
from pathlib import Path

import dola_ethereum_sdk
import dola_ethereum_sdk.init as dola_ethereum_init
import dola_ethereum_sdk.load as dola_ethereum_load
from sui_brownie.parallelism import ThreadExecutor

import dola_sui_sdk
import dola_sui_sdk.init as dola_sui_init
import dola_sui_sdk.lending as dola_sui_lending
import dola_sui_sdk.load as dola_sui_load

FORMAT = '%(asctime)s - %(funcName)s - %(levelname)s - %(name)s: %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger()
logger.setLevel("INFO")


def read_json(file) -> dict:
    try:
        with open(file, "r") as f:
            return json.load(f)
    except:
        return {}


def write_json(file, data: dict):
    with open(file, "w") as f:
        return json.dump(data, f, indent=1, separators=(',', ':'))


class BridgeDict(OrderedDict):
    def __init__(self, file, *args, **kwargs):
        pool_path = Path.home().joinpath(".cache").joinpath("evm").joinpath("bridge_records")
        if not pool_path.exists():
            pool_path.mkdir()
        pool_file = pool_path.joinpath(file)
        self.file = pool_file
        super(BridgeDict, self).__init__(*args, **kwargs)
        self.read_data()

    def read_data(self):
        data = read_json(self.file)
        for k in data:
            self[k] = data[k]

    def __setitem__(self, key, value):
        super(BridgeDict, self).__setitem__(key, value)
        write_json(self.file, self)


def bridge_pool_evm(network):
    data = BridgeDict("evm_bridge_pool.json")
    local_logger = logger.getChild(f"[{network}][bridge_pool]")

    while True:
        local_logger.info("running...")
        pending_datas = []
        try:
            vaa, nonce = dola_ethereum_init.bridge_pool_read_vaa()
            pending_datas.append((vaa, nonce, "ethereum"))
        except:
            pass

        for vaa, nonce, source in pending_datas:
            dv = str(nonce) + vaa
            dk = str(hashlib.sha3_256(dv.encode()).digest().hex())
            if dk not in data:
                decode_vaa = list(bytes.fromhex(vaa.replace("0x", "") if "0x" in vaa else vaa))
                local_logger.info(f"nonce:{nonce}, source:{source}, call type:{decode_vaa[-1]}")
                try:
                    if decode_vaa[-1] == 0:
                        dola_sui_lending.core_supply(vaa)
                    elif decode_vaa[-1] == 1:
                        dola_sui_lending.core_withdraw(vaa)
                    elif decode_vaa[-1] == 2:
                        dola_sui_lending.core_borrow(vaa)
                    elif decode_vaa[-1] == 3:
                        dola_sui_lending.core_repay(vaa)
                    elif decode_vaa[-1] == 5:
                        dola_sui_lending.core_binding(vaa)
                except:
                    traceback.print_exc()
                data[dk] = dv
        time.sleep(5)


def bridge_core_evm(network):
    sui_wormhole_bridge = dola_sui_load.wormhole_bridge_package()
    ethereum_wormhole_bridge = dola_ethereum_load.wormhole_bridge_package()
    ethereum_account = dola_ethereum_sdk.get_account()

    data = BridgeDict("evm_bridge_core.json")
    local_logger = logger.getChild(f"[{network}][bridge_core]")
    while True:
        local_logger.info("running...")
        try:
            vaa, nonce = dola_sui_init.bridge_core_read_vaa()
            decode_payload = sui_wormhole_bridge.bridge_pool.decode_receive_withdraw_payload.simulate(
                vaa
            )["events"][-1]["moveEvent"]["fields"]["pool_address"]["fields"]
            dola_chain_id = decode_payload["dola_chain_id"]

            dv = str(nonce) + vaa
            dk = str(hashlib.sha3_256(dv.encode()).digest().hex())
        except:
            time.sleep(5)
            continue

        if dk not in data:
            local_logger.info(f"Withdraw nonce:{nonce}, dola_chain_id:{dola_chain_id}")
            i = 0
            while i < 3:
                try:
                    if dola_chain_id == dola_ethereum_init.get_wormhole_chain_id():
                        ethereum_wormhole_bridge.receiveWithdraw(vaa, {"from": ethereum_account})
                    break
                except:
                    traceback.print_exc()
                    i = i + 1
                    continue
            data[dk] = dv
        time.sleep(5)


def main():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network("polygon-zk-test")
    pt = ThreadExecutor(executor=2)
    pt.run(
        [functools.partial(bridge_pool_evm, "polygon-zk-test"), functools.partial(bridge_core_evm, "polygon-zk-test")])


if __name__ == "__main__":
    main()
