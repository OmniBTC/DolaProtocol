# @Time    : 2022/11/28 11:07
# @Author  : WeiDai
# @FileName: __init__.py
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
from dotenv import load_dotenv

DOLA_CONFIG = {"DOLA_PROJECT_PATH": Path("../../..")}

DOLA_CONFIG["DOLA_ETHEREUM_PATH"] = DOLA_CONFIG["DOLA_PROJECT_PATH"].joinpath("ethereum")
if DOLA_CONFIG["DOLA_ETHEREUM_PATH"].exists() and DOLA_CONFIG["DOLA_ETHEREUM_PATH"].joinpath("contracts").exists():
    DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"] = project.load(project_path=DOLA_CONFIG["DOLA_ETHEREUM_PATH"])
    DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"].load_config()
else:
    DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"] = None

load_dotenv(DOLA_CONFIG["DOLA_ETHEREUM_PATH"].joinpath(".env"))


def set_dola_project_path(path: Union[Path, str]):
    if isinstance(path, str):
        path = Path(path)
    DOLA_CONFIG["DOLA_PROJECT_PATH"] = path
    DOLA_CONFIG["DOLA_ETHEREUM_PATH"] = DOLA_CONFIG["DOLA_PROJECT_PATH"].joinpath("ethereum")
    DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"] = project.load(project_path=DOLA_CONFIG["DOLA_ETHEREUM_PATH"])
    DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"].load_config()

    assert DOLA_CONFIG["DOLA_ETHEREUM_PATH"].exists(), f"Path error:{DOLA_CONFIG['DOLA_ETHEREUM_PATH'].absolute()}!"


def set_ethereum_network(net: str):
    change_network(net)


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


def zero_address():
    return "0x0000000000000000000000000000000000000000"


def get_chain_id():
    return network.chain.id


def get_account_address():
    return get_account().address
