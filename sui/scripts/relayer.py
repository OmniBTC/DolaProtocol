# @Time    : 2022/12/7 17:21
# @Author  : WeiDai
# @FileName: relayer.py
import contextlib
import hashlib
import json
import logging
import time
import traceback
from collections import OrderedDict
from pathlib import Path

from sui_brownie import CacheObject, ObjectType
from sui_brownie.parallelism import ThreadExecutor

import dola_aptos_sdk
import dola_aptos_sdk.init as dola_aptos_init
import dola_aptos_sdk.load as dola_aptos_load
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
        pool_path = Path.home().joinpath(".cache").joinpath(
            "sui").joinpath("bridge_records")
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
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../.."))
    # dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    # dola_ethereum_sdk.set_ethereum_network("polygon-test")

    data = BridgeDict("sui_bridge_pool.json")
    local_logger = logger.getChild("[bridge_pool]")

    while True:
        local_logger.info("running...")
        pending_datas = []
        with contextlib.suppress(Exception):
            # Read sui
            vaa, nonce = dola_sui_init.bridge_pool_read_vaa()
            pending_datas.append((vaa, nonce, "sui"))
        with contextlib.suppress(Exception):
            # Read aptos
            vaa, nonce = dola_aptos_init.bridge_pool_read_vaa()
            pending_datas.append((vaa, nonce, "aptos"))
        # with contextlib.suppress(Exception):
        #     # Read ethereum (todo! support multi ethereum)
        #     vaa, nonce = dola_ethereum_init.bridge_pool_read_vaa()
        #     if len(vaa) > 0:
        #         pending_datas.append((vaa, nonce, "ethereum"))

        for vaa, nonce, source in pending_datas:
            dv = str(nonce) + vaa
            dk = str(hashlib.sha3_256(dv.encode()).digest().hex())
            if dk not in data:
                decode_vaa = list(bytes.fromhex(
                    vaa.replace("0x", "") if "0x" in vaa else vaa))
                local_logger.info(
                    f"nonce:{nonce}, source:{source}")
                i = 0
                while i < 3:
                    try:
                        call_type = decode_vaa[-1]
                        app_id = decode_vaa[1]
                        if app_id == 0:
                            if call_type == 0:
                                dola_sui_lending.core_binding(vaa)
                            elif call_type == 1:
                                dola_sui_lending.core_unbinding(vaa)
                        elif app_id == 1:
                            if call_type == 0:
                                dola_sui_lending.core_supply(vaa)
                            elif call_type == 1:
                                dola_sui_lending.core_withdraw(vaa)
                            elif call_type == 2:
                                dola_sui_lending.core_borrow(vaa)
                            elif call_type == 3:
                                dola_sui_lending.core_repay(vaa)
                            elif call_type == 4:
                                dola_sui_lending.core_liquidate(vaa)
                            elif call_type == 5:
                                dola_sui_lending.core_as_collateral(vaa)
                            elif call_type == 6:
                                dola_sui_lending.core_cancel_as_collateral(vaa)
                        break
                    except Exception:
                        traceback.print_exc()
                        i += 1
                        continue
                data[dk] = dv
        time.sleep(1)


def bridge_core():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../.."))
    # dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    # dola_ethereum_sdk.set_ethereum_network("polygon-test")

    sui_omnipool = dola_sui_load.omnipool_package()
    aptos_omnipool = dola_aptos_load.omnipool_package()
    # ethereum_wormhole_bridge = dola_ethereum_load.wormhole_bridge_package()
    # ethereum_account = dola_ethereum_sdk.get_account()

    data = BridgeDict("sui_bridge_core.json")
    local_logger = logger.getChild("[bridge_core]")
    while True:
        local_logger.info("running...")
        try:
            vaa, nonce = dola_sui_init.bridge_core_read_vaa()
            decode_payload = \
                sui_omnipool.wormhole_adapter_pool.decode_withdraw_payload.simulate(
                    vaa
                )["events"][-1]["moveEvent"]["fields"]["pool_address"]["fields"]
            token_name = decode_payload["dola_address"]
            dola_chain_id = decode_payload["dola_chain_id"]
            if dola_chain_id in [0, 1]:
                token_name = bytes(token_name).decode("ascii")
                if token_name[:2] != "0x":
                    token_name = f"0x{token_name}"
            dv = str(nonce) + vaa
            dk = str(hashlib.sha3_256(dv.encode()).digest().hex())
        except Exception:
            time.sleep(1)
            continue

        if dk not in data:
            local_logger.info(
                f"Withdraw nonce:{nonce}, dola_chain_id:{dola_chain_id}")
            sui_wormhole = dola_sui_load.wormhole_package()
            sui_account_address = sui_omnipool.account.account_address
            i = 0
            while i < 3:
                try:
                    if dola_chain_id == 0:
                        sui_omnipool.wormhole_adapter_pool.receive_withdraw(
                            sui_wormhole.state.State[-1],
                            sui_omnipool.bridge_pool.PoolState[-1],
                            CacheObject[ObjectType.from_type(
                                dola_sui_init.pool(token_name))][sui_account_address][-1],
                            vaa,
                            ty_args=[token_name]
                        )
                    elif dola_chain_id == 1:
                        aptos_omnipool.wormhole_adapter_pool.receive_withdraw(
                            vaa,
                            ty_args=[token_name]
                        )
                    # elif dola_chain_id == dola_ethereum_init.get_wormhole_chain_id():
                    #     ethereum_wormhole_bridge.receiveWithdraw(
                    #         vaa, {"from": ethereum_account})
                    break
                except Exception as e:
                    traceback.print_exc()
                    i += 1
                    continue
            data[dk] = dv
        time.sleep(1)


def main():
    pt = ThreadExecutor(executor=2)
    pt.run([bridge_pool, bridge_core])


if __name__ == "__main__":
    main()
