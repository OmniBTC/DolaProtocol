import contextlib
import functools
import json
from pathlib import Path
from typing import Union, List

from brownie import (
    network,
    accounts,
    config,
    project,
    web3
)
from brownie.network.web3 import Web3
from brownie.network import priority_fee
from multiprocessing import Queue, Process, set_start_method

from brownie.project import get_loaded_projects

NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS = [
    "hardhat", "development", "ganache"]
LOCAL_BLOCKCHAIN_ENVIRONMENTS = NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS + [
    "mainnet-fork",
    "binance-fork",
    "matic-fork",
]


def hex_str_to_vector_u8(data: str) -> List[int]:
    assert judge_hex_str(data)
    return list(bytearray.fromhex(data.replace("0x", "")))


def judge_hex_str(data: str):
    if not data.startswith("0x"):
        return False
    if len(data) % 2 != 0:
        return False
    try:
        web3.toInt(hexstr=data)
        return True
    except Exception:
        return False


def to_hex_str(data: str):
    return data if judge_hex_str(data) else "0x" + bytes(data, 'ascii').hex()


def get_account(index=None, id=None):
    if index:
        return accounts[index]
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        return accounts[0]
    return accounts.load(id) if id else accounts.add(config["wallets"]["from_key"])


def get_func_prototype(data):
    func_prototype = ""
    for index1, params in enumerate(data):
        if index1 > 0:
            func_prototype += ','
        if params['type'] in ['tuple', 'tuple[]']:
            func_prototype += '('
            func_prototype += get_func_prototype(params['components'])
            func_prototype += ')'
        else:
            func_prototype += params['type']
        if params['type'] == 'tuple[]':
            func_prototype += "[]"
    return func_prototype


def get_method_signature_by_abi(abi):
    result = {}
    for d in abi:
        if d["type"] != "function":
            continue
        func_name = d["name"]
        func_prototype = get_func_prototype(d["inputs"])
        func_prototype = f"{func_name}({func_prototype})"
        result[func_name] = Web3.sha3(text=func_prototype)[:4]
    return result


def get_event_signature_by_abi(abi):
    result = {}
    for d in abi:
        if d["type"] != "event":
            continue
        func_name = d["name"]
        func_prototype = get_func_prototype(d["inputs"])
        func_prototype = f"{func_name}({func_prototype})"
        result[func_name] = Web3.sha3(text=func_prototype)
    return result


def change_network(dst_net):
    if network.show_active() == dst_net:
        return
    if network.is_connected():
        network.disconnect()
    network.connect(dst_net)
    if dst_net in ["rinkeby"]:
        priority_fee("2 gwei")


def zero_address():
    return "0x0000000000000000000000000000000000000000"


def read_json(file):
    try:
        with open(file) as f:
            return json.load(f)
    except Exception:
        return []


def padding_to_bytes(data: str, padding="right", length=32):
    data = data.removeprefix("0x")
    padding_length = length * 2 - len(data)
    if padding == "right":
        return f"0x{data}" + "0" * padding_length
    else:
        return "0x" + "0" * padding_length + data


def combine_bytes(bs: list):
    output = "0x"
    for b in bs:
        output += b.replace("0x", "")
    return output


def find_loaded_projects(name):
    for loaded_project in get_loaded_projects():
        if loaded_project._name == name:
            return loaded_project


class TaskType:
    Execute = "execute"
    ExecuteWithProject = "execute_with_project"


class Session(Process):
    def __init__(self, net: str, project_path: Union[Path, str, None], group=None, name=None, kwargs=None, *, daemon=None):
        if kwargs is None:
            kwargs = {}
        self.net = net
        self.project_path = project_path
        with contextlib.suppress(Exception):
            set_start_method("spawn")
        self.task_queue = Queue(maxsize=1)
        self.result_queue = Queue(maxsize=1)

        super().__init__(
            group=group,
            target=self.work,
            name=name,
            args=(self.task_queue, self.result_queue),
            kwargs=kwargs,
            daemon=daemon
        )
        self.start()

    def work(self,
             task_queue: Queue,
             result_queue: Queue):
        p = project.load(self.project_path, name=self.name)
        p.load_config()
        change_network(self.net)
        print(f"network {self.net} is connected!")
        while True:
            task_type, task = task_queue.get()
            if task_type == TaskType.Execute:
                result_queue.put(task())
            else:
                result_queue.put(task(p=p))

    def put_task(self, func, args=(), with_project=False):
        task = functools.partial(func, *args)
        if with_project:
            self.task_queue.put((TaskType.ExecuteWithProject, task))
        else:
            self.task_queue.put((TaskType.Execute, task))
        return self.result_queue.get()


def get_chain_id():
    return network.chain.id


def get_account_address():
    return get_account().address



def get_wormhole_chain_id():
    return config["networks"][network.show_active()]["wormhole_chainid"]


def get_wormhole():
    return config["networks"][network.show_active()]["wormhole"]
