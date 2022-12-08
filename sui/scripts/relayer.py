# @Time    : 2022/12/7 17:21
# @Author  : WeiDai
# @FileName: relayer.py
import base64
import json
import time
from collections import OrderedDict
from pathlib import Path

from scripts import load
from scripts.init import pool
from scripts.lending import core_supply, core_withdraw, core_borrow, core_repay
from sui_brownie import CacheObject, ObjectType


def read_json(file) -> dict:
    try:
        with open(file, "r") as f:
            return json.load(f)
    except:
        return {}


def write_json(file, data: dict):
    with open(file, "w") as f:
        return json.dump(data, f)


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

    wormhole_bridge = load.wormhole_bridge_package()
    while True:
        vaa = wormhole_bridge.bridge_pool.read_vaa.simulate(
            wormhole_bridge.bridge_pool.PoolState[-1], 0
        )["events"][-1]["moveEvent"]["fields"]["vaa"]
        if hash(vaa) not in data:
            decode_vaa = list(base64.b64decode(vaa))
            if decode_vaa[-1] == 0:
                core_supply(vaa)
            elif decode_vaa[-1] == 1:
                core_withdraw(vaa)
            elif decode_vaa[-1] == 2:
                core_borrow(vaa)
            elif decode_vaa[-1] == 3:
                core_repay(vaa)
            data[hash(vaa)] = vaa
        time.sleep(60)


def bridge_core():
    data = BridgeDict("bridge_core.json")
    wormhole_bridge = load.wormhole_bridge_package()
    while True:
        vaa = wormhole_bridge.bridge_core.read_vaa.simulate(
            wormhole_bridge.bridge_pool.PoolState[-1], 0
        )["events"][-1]["moveEvent"]["fields"]["vaa"]
        decode_vaa = list(base64.b64decode(vaa))
        token_name = wormhole_bridge.bridge_pool.decode_receive_withdraw_payload.simulate(
            decode_vaa
        )["events"][-1]["moveEvent"]["fields"]["token_name"]
        if hash(vaa) not in data:
            wormhole = load.wormhole_package()
            wormhole_bridge = load.wormhole_bridge_package()
            account_address = wormhole_bridge.account.account_address
            wormhole_bridge.bridge_pool.receive_withdraw(
                wormhole.state.State[-1],
                wormhole_bridge.bridge_pool.PoolState[-1],
                CacheObject[ObjectType.from_type(pool(token_name))][account_address][-1],
                list(base64.b64decode(vaa)),
                ty_args=[token_name]
            )
        time.sleep(60)
