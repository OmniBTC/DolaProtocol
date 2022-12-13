# @Time    : 2022/12/7 17:21
# @Author  : WeiDai
# @FileName: relayer.py
import base64
import hashlib
import json
import logging
import time
from collections import OrderedDict
from multiprocessing import set_start_method
from pathlib import Path

from sui_brownie import CacheObject, ObjectType
from sui_brownie.parallelism import ProcessExecutor

import load
from init import pool
from lending import core_supply, core_withdraw, core_borrow, core_repay

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
        pool_path = Path.home().joinpath(".cache")
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


def bridge_pool():
    data = BridgeDict("bridge_pool.json")
    local_logger = logger.getChild(f"[bridge_pool]")

    wormhole_bridge = load.wormhole_bridge_package()
    while True:
        try:
            result = wormhole_bridge.bridge_pool.read_vaa.simulate(
                wormhole_bridge.bridge_pool.PoolState[-1], 0
            )["events"][-1]["moveEvent"]["fields"]
            vaa = result["vaa"]
            nonce = result["nonce"]
        except:
            time.sleep(10)
            continue
        dv = str(nonce) + vaa
        dk = str(hashlib.sha3_256(dv.encode()).digest().hex())
        if dk not in data:
            local_logger.info(nonce)
            decode_vaa = list(base64.b64decode(vaa))
            if decode_vaa[-1] == 0:
                core_supply(vaa)
            elif decode_vaa[-1] == 1:
                core_withdraw(vaa)
            elif decode_vaa[-1] == 2:
                core_borrow(vaa)
            elif decode_vaa[-1] == 3:
                core_repay(vaa)
            data[dk] = dv
        time.sleep(10)


def bridge_core():
    data = BridgeDict("bridge_core.json")
    wormhole_bridge = load.wormhole_bridge_package()
    local_logger = logger.getChild(f"[bridge_core]")
    while True:
        try:
            result = wormhole_bridge.bridge_core.read_vaa.simulate(
                wormhole_bridge.bridge_core.CoreState[-1], 0
            )["events"][-1]["moveEvent"]["fields"]
            vaa = result["vaa"]
            nonce = result["nonce"]
        except:
            time.sleep(10)
            continue
        decode_vaa = list(base64.b64decode(vaa))
        catalog = wormhole_bridge.bridge_pool.decode_receive_withdraw_payload.simulate(
            decode_vaa
        )["events"][-1]["moveEvent"]["fields"]["catalog"]
        catalog = "0x" + base64.b64decode(catalog).decode("ascii")
        dv = str(nonce) + vaa
        dk = str(hashlib.sha3_256(dv.encode()).digest().hex())
        if dk not in data:
            local_logger.info(nonce)
            wormhole = load.wormhole_package()
            wormhole_bridge = load.wormhole_bridge_package()
            account_address = wormhole_bridge.account.account_address
            i = 0
            while i < 3:
                try:
                    wormhole_bridge.bridge_pool.receive_withdraw(
                        wormhole.state.State[-1],
                        wormhole_bridge.bridge_pool.PoolState[-1],
                        CacheObject[ObjectType.from_type(pool(catalog))][account_address][-1],
                        list(base64.b64decode(vaa)),
                        ty_args=[catalog]
                    )
                    break
                except:
                    i = i + 1
                    continue
            data[dk] = dv
        time.sleep(10)


def main():
    set_start_method("spawn")
    pt = ProcessExecutor(executor=2)
    pt.run([bridge_pool, bridge_core])


if __name__ == "__main__":
    main()
