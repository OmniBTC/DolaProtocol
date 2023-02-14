from __future__ import annotations

import base64
import copy
import functools
import json
import os
import threading
import time
import traceback
from collections import OrderedDict
from pathlib import Path
from typing import Union, List, Dict
from pprint import pprint, pformat
from retrying import retry

import httpx
from dotenv import dotenv_values

from .account import Account

import yaml
import toml

from .parallelism import ThreadExecutor


class ObjectType:
    __single_object: Dict[str, ObjectType] = dict()

    def __init__(self,
                 package_id: str,
                 module_name: str,
                 struct_name: str
                 ):
        self.package_id = package_id
        self.module_name = module_name
        self.struct_name = struct_name
        self.package_name = ""
        assert str(self) not in self.__single_object, "Has exist, use from_data"

    @classmethod
    def from_data(
            cls,
            package_id: str,
            module_name: str,
            struct_name: str) -> ObjectType:
        data = f"{package_id}::{module_name}::{struct_name}"
        if data not in cls.__single_object:
            cls.__single_object[data] = ObjectType(package_id, module_name, struct_name)
        return cls.__single_object[data]

    @staticmethod
    def normal_package_id(package_id) -> str:
        if package_id == "0x2":
            return package_id
        if package_id[:2] == "0x" and len(package_id[2:]) < 40:
            package_id = f"0x{'0' * (40 - len(package_id[2:]))}{package_id[2:]}"
        return package_id

    @classmethod
    def normal_data(cls, data: str):
        data = data.split("::")
        for k in range(len(data)):
            index = data[k].find("0x")
            data[k] = data[k][:index] + cls.normal_package_id(data[k][index:])
        return "::".join(data)

    @classmethod
    def from_type(cls, data: str) -> ObjectType:
        """
        :param data:
            0xb5189942a34446f1d037b446df717987e20a5717::main1::Hello
        :return:
        """
        data = cls.normal_data(data)
        data = data.split("::")
        result = data[:2]
        result.append("::".join(data[2:]))

        return cls.from_data(*result)

    @staticmethod
    def is_object_type(data: str) -> bool:
        if not isinstance(data, str):
            return False
        return len(data.split("::")) >= 3

    def __repr__(self):
        return self.__str__()

    def __str__(self):
        return f"{self.package_id}::{self.module_name}::{self.struct_name}"

    def __hash__(self):
        return hash(str(self))

    def normal_struct(self):
        if self.struct_name is None:
            return []
        elif self.struct_name[-1] == ">":
            index = self.struct_name.find("<")
            return [self.struct_name[:index], self.struct_name[index + 1:-1]]
        else:
            return [self.struct_name]


CACHE_DIR = Path(os.environ.get('HOME')).joinpath(".cache")
if not CACHE_DIR.exists():
    CACHE_DIR.mkdir()

CACHE_FILE = CACHE_DIR.joinpath("objects.json")


class RWList(list):
    def __init__(self, rw_name="", write_flag=False, *args, **kwargs):
        self.rw_name = rw_name
        self.write_flag = write_flag
        super(RWList, self).__init__(*args, **kwargs)

    def append(self, *args, **kwargs) -> None:
        if self.write_flag:
            print(f"RWList write {self.rw_name} of {args[0]}")
        super(RWList, self).append(*args, **kwargs)


class RWDict(OrderedDict):

    def __init__(self, rw_name="", read_flag=False, write_flag=False, *args, **kwargs):
        self.rw_name = rw_name
        self.read_flag = read_flag
        self.write_flag = write_flag
        super(RWDict, self).__init__(*args, **kwargs)

    def __getitem__(self, item):
        if self.read_flag:
            print(f"RWDict read {self.rw_name} of {item}")
        return super(RWDict, self).__getitem__(item)

    def __setitem__(self, key, value):
        if self.write_flag:
            print(f"RWDict write {self.rw_name} of {key} {value}")
        return super(RWDict, self).__setitem__(key, value)


class ThirdCacheList(RWList):
    def append(self, *args, **kwargs) -> None:
        super(ThirdCacheList, self).append(*args, **kwargs)
        persist_cache()


class SecondCacheDict(RWDict):
    def __setitem__(self, key, value):
        if isinstance(value, list):
            kv = ThirdCacheList(rw_name=f"{self.rw_name.replace('second', 'value')}", write_flag=False)
            for v in value:
                kv.append(v)
        else:
            raise ValueError
        super(SecondCacheDict, self).__setitem__(key, kv)
        persist_cache()

    def __getitem__(self, item):
        if item not in self and "Shared" in self:
            self.__setitem__(item, copy.deepcopy(self["Shared"]))

        return super(SecondCacheDict, self).__getitem__(item)


CachePersistLock = threading.Lock()


class TopCacheDict(RWDict):

    def __getitem__(self, item):
        if item in self:
            return super(TopCacheDict, self).__getitem__(item)

        if ObjectType.is_object_type(item) and ObjectType.from_type(item) in self:
            item = ObjectType.from_type(item)

        return super(TopCacheDict, self).__getitem__(item)

    def get(self, key):
        if key in self:
            return super(TopCacheDict, self).get(key)

        if ObjectType.is_object_type(key) and ObjectType.from_type(key) in self:
            key = ObjectType.from_type(key)

        return super(TopCacheDict, self).get(key)

    def __setitem__(self, key, value):
        if isinstance(value, dict):
            kv = SecondCacheDict(rw_name=self.rw_name.replace("top", "second"), write_flag=False)
            for k in value:
                kv[k] = value[k]
        else:
            raise ValueError
        super(TopCacheDict, self).__setitem__(key, kv)
        persist_cache()

    def fuzzy_search_package(self, key):
        keys = {k.lower().replace("_", ""): k for k in list(self.keys()) if isinstance(k, str)}
        key = key.lower().replace("_", "")
        if key in keys:
            data = self[keys[key]].get("Shared", [])
            if len(data):
                return data[-1]
        return None


CacheObject: Dict[Union[ObjectType, str], dict] = TopCacheDict(rw_name="CacheObject-top", write_flag=False)


def persist_cache(cache_file=CACHE_FILE):
    data = {}
    for k in CacheObject:
        for m in CacheObject[k]:
            if len(CacheObject[k][m]):
                if str(k) not in data:
                    data[str(k)] = {}
                data[str(k)][m] = CacheObject[k][m]
    if len(data) == 0:
        return

    pt = ThreadExecutor(executor=1, mode="all")

    def worker():
        with open(str(cache_file), "w") as f:
            json.dump(data, f, indent=4, sort_keys=True)

    CachePersistLock.acquire()
    pt.run([worker])
    CachePersistLock.release()


def reload_cache(cache_file: Path = CACHE_FILE):
    if not cache_file.exists():
        return
    with open(str(cache_file), "r") as f:
        try:
            data = json.load(f)
        except:
            data = {}
        for k in data:
            try:
                object_type = ObjectType.from_type(k)
                for v in data[k]:
                    for v1 in data[k][v]:
                        insert_cache(object_type, v1, v)
            except:
                for v in data[k]:
                    for v1 in data[k][v]:
                        insert_package(k, v1)


def insert_coin(coin_type: str, object_id: str, owner: str):
    """
    :param coin_type: 0x2::sui::SUI
    :param object_id:
    :param owner:
    :return:
    """
    insert_cache(ObjectType.from_type(f'0x2::coin::Coin<{coin_type}>'), object_id, owner)


def insert_package(package_name, object_id: str = None):
    if object_id is None:
        return
    if package_name not in CacheObject:
        CacheObject[package_name] = {"Shared": []}
        setattr(CacheObject, package_name, CacheObject[package_name]["Shared"])
    if object_id not in CacheObject[package_name]["Shared"]:
        CacheObject[package_name]["Shared"].append(object_id)


def insert_cache(object_type: ObjectType, object_id: str = None, owner="Shared"):
    if object_type not in CacheObject:
        CacheObject[object_type] = {owner: [object_id]} if object_id is not None else {owner: []}
        final_object = CacheObject
        attr_list = [object_type.module_name, object_type.struct_name]
        for k, attr in enumerate(attr_list):
            if hasattr(final_object, attr):
                final_object = getattr(final_object, attr)
            else:
                if k == len(attr_list) - 1:
                    struct_names = object_type.normal_struct()
                    if len(struct_names) == 0:
                        return
                    # correct name
                    attr = struct_names[0]
                    ob = dict()
                else:
                    ob = type(f"CacheObject_{object_type.module_name}", (object,), dict())()
                setattr(final_object, attr, ob)
                final_object = ob
            if k == len(attr_list) - 1 and object_type not in final_object:
                final_object[object_type] = CacheObject[object_type]
    elif object_id is not None:
        if owner not in CacheObject[object_type]:
            CacheObject[object_type][owner] = []
        if object_id not in CacheObject[object_type][owner]:
            CacheObject[object_type][owner].append(object_id)


reload_cache()


class ApiError(Exception):
    """Error thrown when the API returns >= 400"""

    def __init__(self, message, status_code):
        # Call the base class constructor with the parameters it needs
        super().__init__(message)
        self.status_code = status_code


class SuiCliConfig:

    def __init__(self,
                 file,
                 rpc: str,
                 network: str,
                 account: Account):
        if isinstance(file, Path):
            self.file = file
        else:
            self.file = Path(file)
        self.rpc = rpc

        self.network = network.split("-")[-1].lower()
        self.account = account
        self.tmp_keystore = self.file.parent.joinpath(".env.keystore")

    def __enter__(self):
        self.active_config()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.file.exists():
            self.file.unlink()

        if self.tmp_keystore.exists():
            self.tmp_keystore.unlink()

    def active_config(self):
        template_config_file = Path(__file__).parent.joinpath("sui_config.template.yaml")
        with open(template_config_file, "r") as f:
            config_data = f.read()

        template_keystore_file = Path(__file__).parent.joinpath("sui_keystore.template.keystore")
        with open(template_keystore_file, "r") as f:
            keystore_data = f.read()
        keystore_data = keystore_data.replace("{keystore}", self.account.keystore())

        with open(self.tmp_keystore, "w") as f:
            f.write(keystore_data)

        config_data = config_data \
            .replace("{file}", str(self.tmp_keystore.absolute())) \
            .replace("{network}", self.network) \
            .replace("{rpc}", self.rpc) \
            .replace("{active_address}", self.account.account_address)
        with open(self.file, "w") as f:
            f.write(config_data)


class MoveToml:
    def __init__(self, file: str):
        self.file = file
        with open(file, "r") as f:
            data = toml.load(f)
        self.origin_data = data
        self.data = copy.deepcopy(data)

    def __getitem__(self, item):
        return self.data[item]

    def __setitem__(self, key, value):
        self.data[key] = value

    def store(self):
        with open(self.file, "w") as f:
            toml.dump(self.data, f)

    def restore(self):
        with open(self.file, "w") as f:
            toml.dump(self.origin_data, f)

    def get(self, param, param1):
        return self.data.get(param, param1)

    def keys(self):
        return self.data.keys()


class Coin:
    __single_object: Dict[str, Coin] = dict()

    def __init__(self,
                 object_id: str,
                 owner: str,
                 balance: int,
                 ):
        self.object_id = object_id
        self.owner = owner
        self.balance = int(balance)
        assert self.object_id not in self.__single_object

    @classmethod
    def from_data(cls,
                  object_id: str,
                  owner: str,
                  balance: int,
                  ) -> Coin:
        if object_id in cls.__single_object:
            cls.__single_object[object_id].owner = owner
            cls.__single_object[object_id].balance = balance
        else:
            cls.__single_object[object_id] = Coin(object_id, owner, balance)
        return cls.__single_object[object_id]

    def __repr__(self):
        return self.__str__()

    def __str__(self):
        return json.dumps(dict(object_id=self.object_id, owner=self.owner, balance=self.balance))


class HttpClient(httpx.Client):

    @retry(stop_max_attempt_number=5, wait_random_min=500, wait_random_max=1000)
    def get(self, *args, **kwargs):
        return super().get(*args, **kwargs)

    @retry(stop_max_attempt_number=5, wait_random_min=500, wait_random_max=1000)
    def post(self, *args, **kwargs):
        response = super().post(*args, **kwargs)
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        return response


class SuiDynamicFiled:

    @staticmethod
    def format_bytes(d: bytes):
        try:
            da = d.decode("ascii")
        except:
            return "0x" + d.hex()
        for v in da:
            if '0' <= v <= "9" or 'a' <= v <= "z" or 'A' <= v <= "Z" or v == ":":
                continue
            return "0x" + d.hex()
        return da

    @classmethod
    def format_data(cls, d):
        """
        :param d:
            bytes --> ascii | hex (padding 0x)
            str --> str
        :return:
        """
        try:
            return int(d)
        except:
            pass
        if isinstance(d, list):
            for k in range(len(d)):
                d[k] = cls.format_data(d[k])
            try:
                return cls.format_bytes(bytes(d))
            except:
                pass
        elif isinstance(d, dict):
            for k in list(d.keys()):
                if k == "fields":
                    for m in d[k]:
                        try:
                            d[k][m] = cls.format_data(d[k][m])
                        except:
                            pass
                elif k == "type":
                    pass
                else:
                    d[k] = cls.format_data(d[k])
        return d

    def __init__(self, owner, uid, name, value, ty):
        self.owner = owner
        self.uid = uid
        self.name_type, self.value_type = self.format_type(ty)
        self.name = self.format_data(name)
        self.value = self.format_data(value)

    @staticmethod
    def format_type(data: str) -> (str, str):
        data = data.replace("0x2::dynamic_field::Field<", "")[:-1]
        data = data.split(",")
        return data[0], ",".join(data[1:])

    def __repr__(self):
        return self.__str__()

    def __str__(self):
        if isinstance(self.name, str):
            name = self.name
        else:
            name = str(pformat(self.name, compact=True))

        return str(pformat({name: self.value}, compact=True))


def validator_retry(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        while True:
            try:
                result = func(*args, **kwargs)
                return result
            except Exception as e:
                if "validators" in str(e):
                    print("validators error:", e)
                    time.sleep(5)
                else:
                    raise e

    return wrapper


class SuiPackage:
    def __init__(self,
                 brownie_config: Union[Path, str] = Path.cwd(),
                 network: str = "sui-devnet",
                 is_compile: bool = False,
                 package_id: str = None,
                 package_path: Union[Path, str] = None,
                 mnemonic: str = None
                 ):
        """
        :param brownie_config: The folder where brownie-config.yaml is located.
        :param network:
        :param is_compile:
        :param package_path: The folder where Move.toml is located. Mostly the same as brownie_config.
        """
        self.package_id = package_id
        if isinstance(brownie_config, Path):
            self.brownie_config = brownie_config
        else:
            self.brownie_config = Path(brownie_config)

        self.network = network

        if package_path is None:
            self.package_path = self.brownie_config
        elif isinstance(package_path, str):
            self.package_path = Path(package_path)
        else:
            self.package_path = package_path

        # # # # # load config
        assert self.brownie_config.joinpath(
            "brownie-config.yaml").exists(), "brownie-config.yaml not found"
        self.config_path = self.brownie_config.joinpath("brownie-config.yaml")
        self.config = {}  # all network configs
        with self.config_path.open() as fp:
            self.config = yaml.safe_load(fp)
        try:
            env = dotenv_values(self.brownie_config.joinpath(self.config["dotenv"]))
            self.private_key = None
            self.mnemonic = None
            if mnemonic is not None:
                self.mnemonic = mnemonic
            elif env.get("PRIVATE_KEY_SUI", None) is not None:
                self.private_key = env.get("PRIVATE_KEY_SUI")
            elif env.get("PRIVATE_KEY", None) is not None:
                self.private_key = env.get("PRIVATE_KEY")
            elif env.get("MNEMONIC_SUI", None) is not None:
                self.mnemonic = env.get("MNEMONIC_SUI")
            elif env.get("MNEMONIC", None) is not None:
                self.mnemonic = env.get("MNEMONIC")
            else:
                raise EnvironmentError

            if self.private_key is not None:
                self.account = Account.load_key(self.private_key)
            elif self.mnemonic is not None:
                self.account = Account.load_mnemonic(self.mnemonic)
        except Exception as e:
            raise e

        # current aptos network config
        self.network_config = self.config["networks"][network]
        self.base_url = self.config["networks"][network]["node_url"]
        self.client = HttpClient(timeout=30)

        # # # # # load move toml
        assert self.package_path.joinpath(
            "Move.toml").exists(), "Move.toml not found"
        self.move_path = self.package_path.joinpath("Move.toml")
        self.move_toml = {}
        with self.move_path.open() as fp:
            self.move_toml = toml.load(fp)
        self.package_name = self.move_toml["package"]["name"]

        if is_compile:
            self.compile()

        # # # # # Bytecode
        self.build_path = self.package_path.joinpath(
            f"build/{self.package_name}")
        self.move_module_files = []
        bytecode_modules = self.build_path.joinpath("bytecode_modules")
        if bytecode_modules.exists():
            for m in os.listdir(bytecode_modules):
                if str(m).endswith(".mv"):
                    self.move_module_files.append(
                        bytecode_modules.joinpath(str(m)))
        self.move_modules = []
        for m in self.move_module_files:
            with open(m, "rb") as f:
                self.move_modules.append(f.read())

        # # # # # # Abis
        self.abis = {}
        reload_cache(CACHE_FILE)
        self.get_abis()

        # # # # # # Sui cli config
        self.cli_config_file = CACHE_DIR.joinpath(".cli.yaml")
        self.cli_config = SuiCliConfig(self.cli_config_file, self.base_url, self.network, self.account)

        # # # # # # filter result
        self.filter_result_key = ["disassembled", "signers_map"]

    def compile(self):
        # # # # # Compile
        view = f"Compile {self.package_name}"
        print("\n" + "-" * 50 + view + "-" * 50)
        compile_cmd = f"sui move build --abi --path {self.package_path}"
        print(compile_cmd)
        os.system(compile_cmd)
        print("-" * (100 + len(view)))
        print("\n")

    @staticmethod
    def base64(data: Union[str, list]):
        if isinstance(data, str):
            return base64.b64encode(data)
        else:
            return [base64.b64encode(d).decode("ascii") for d in data]

    def format_dict(self, data):
        for k in list(data.keys()):
            if k in self.filter_result_key:
                del data[k]
                continue
            if isinstance(data[k], list):
                self.format_list(data[k])
            elif isinstance(data[k], dict):
                self.format_dict(data[k])

    def format_list(self, data):
        for v in data:
            if isinstance(v, list):
                self.format_list(v)
            elif isinstance(v, dict):
                self.format_dict(v)

    def format_result(self, data):
        if data is None:
            return
        if isinstance(data, list):
            self.format_list(data)
        if isinstance(data, dict):
            self.format_dict(data)
        return data

    @staticmethod
    def replace_toml(move_toml: MoveToml, replace_address: dict = None):
        for k in list(move_toml.get("addresses", dict()).keys()):
            if k in replace_address:
                if replace_address[k] is not None:
                    move_toml["addresses"][k] = replace_address[k]
                elif CacheObject.fuzzy_search_package(k) is not None:
                    move_toml["addresses"][k] = CacheObject.fuzzy_search_package(k)
                else:
                    assert False, "replace address is None"
        return move_toml

    def replace_addresses(
            self,
            replace_address: dict = None,
            output: dict = None
    ) -> dict:
        if replace_address is None:
            return output
        if output is None:
            output = dict()
        current_move_toml = MoveToml(self.move_path)
        if current_move_toml["package"]["name"] in output:
            return output
        output[current_move_toml["package"]["name"]] = current_move_toml

        # process current move toml
        self.replace_toml(current_move_toml, replace_address)

        # process dependencies move toml
        for k in list(current_move_toml.keys()):
            if "dependencies" == k:
                for d in list(current_move_toml[k].keys()):
                    # process local
                    if "local" in current_move_toml[k][d]:
                        local_path = self.package_path \
                            .joinpath(current_move_toml[k][d]["local"])
                        assert local_path.exists(), f"{local_path.absolute()} not found"
                        dep_move_toml = SuiPackage(
                            brownie_config=self.brownie_config,
                            network=self.network,
                            is_compile=False,
                            package_path=local_path)
                        dep_move_toml.replace_addresses(replace_address, output)
                    # process remote
                    else:
                        git_index = current_move_toml[k][d]["git"].rfind("/")
                        git_path = current_move_toml[k][d]["git"][:git_index + 1]
                        git_file = current_move_toml[k][d]["git"][git_index + 1:]
                        if "subdir" not in current_move_toml[k][d]:
                            git_file = f"{d}.git"
                            sub_dir = ""
                        else:
                            sub_dir = current_move_toml[k][d]["subdir"]
                        git_file = (git_path + git_file + f"_{current_move_toml[k][d]['rev']}") \
                            .replace("://", "___") \
                            .replace("/", "_").replace(".", "_")
                        remote_path = Path(f"{os.environ.get('HOME')}/.move") \
                            .joinpath(git_file) \
                            .joinpath(sub_dir)
                        assert remote_path.exists(), f"{remote_path.absolute()} not found"
                        dep_move_toml = SuiPackage(
                            brownie_config=self.brownie_config,
                            network=self.network,
                            is_compile=False,
                            package_path=remote_path)
                        dep_move_toml.replace_addresses(replace_address, output)

        for k in output:
            output[k].store()
        return output

    @retry(stop_max_attempt_number=3, wait_random_min=500, wait_random_max=1000)
    def publish_package(
            self,
            gas_budget=10000,
            replace_address: dict = None
    ):
        replace_tomls = self.replace_addresses(replace_address=replace_address, output=dict())
        view = f"Publish {self.package_name}"
        print("\n" + "-" * 50 + view + "-" * 50)
        try:
            with self.cli_config as cof:
                compile_cmd = f"sui client --client.config {cof.file.absolute()} publish " \
                              f"--gas-budget {gas_budget} --abi --json {self.package_path.absolute()}"
                with os.popen(compile_cmd) as f:
                    result = f.read()
                try:
                    result = json.loads(result[result.find("{"):])
                    result = self.format_result(result)
                except:
                    pprint(result)
                self.add_details(result.get("effects", dict()))
                pprint(result)
                for d in result.get("effects").get("created", []):
                    if "data" in d and "dataType" in d["data"]:
                        if d["data"]["dataType"] == "package":
                            self.package_id = d["reference"]["objectId"]
                            insert_package(self.package_name, self.package_id)
                            self.get_abis()
            print("-" * (100 + len(view)))
            print("\n")
            for k in replace_tomls:
                replace_tomls[k].restore()
        except Exception as e:
            for k in replace_tomls:
                replace_tomls[k].restore()
            assert False, e

        # For ubuntu has some issue
        # view = f"Publish {self.package_name}"
        # print("\n" + "-" * 50 + view + "-" * 50)
        # response = self.client.post(
        #     f"{self.base_url}",
        #     json={
        #         "jsonrpc": "2.0",
        #         "id": 1,
        #         "method": "sui_publish",
        #         "params": [
        #             self.account.account_address,
        #             self.base64(self.move_modules),
        #             None,
        #             gas_budget
        #         ]
        #     },
        # )
        # result = response.json()
        # result = self.execute_transaction(tx_bytes=result["result"]["txBytes"])
        # # # # # Update package id
        # for d in result.get("created", []):
        #     if "data" in d and "dataType" in d["data"]:
        #         if d["data"]["dataType"] == "package":
        #             self.package_id = d["reference"]["objectId"]
        #             self.get_abis()
        #
        # pprint(result)
        # print("-" * (100 + len(view)))
        # print("\n")
        return result

    def dry_run_transaction(self,
                            tx_bytes
                            ):
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_dryRunTransaction",
                "params": [
                    tx_bytes
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return result

    def add_details(self, result):
        """

        :param result: effects
        :return:
        """
        object_ids = []
        for k in ["created", "mutated"]:
            for d in result.get(k, dict()):
                if "reference" in d and "objectId" in d["reference"]:
                    object_ids.append(d["reference"]["objectId"])
        if len(object_ids):
            cached_object_ids = set()
            object_details = self.get_objects(object_ids)
            for k in ["created", "mutated"]:
                for i, d in enumerate(result.get(k, dict())):
                    if "reference" in d and "objectId" in d["reference"] \
                            and d["reference"]["objectId"] in object_details:
                        object_detail = object_details[d["reference"]["objectId"]]
                        result[k][i] = object_detail
                        if "data" in object_detail and "type" in object_detail["data"]:
                            object_type = ObjectType.from_type(object_detail["data"]["type"])
                            if "Shared" in object_detail["owner"]:
                                insert_cache(object_type, d["reference"]["objectId"])
                                insert_cache(object_type, d["reference"]["objectId"], self.account.account_address)
                                cached_object_ids.add(d["reference"]["objectId"])
                            else:
                                try:
                                    insert_cache(object_type, d["reference"]["objectId"],
                                                 object_detail["owner"]["AddressOwner"])
                                    cached_object_ids.add(d["reference"]["objectId"])
                                except:
                                    pass
            remain_object_ids = cached_object_ids - set(object_ids)
            if len(remain_object_ids):
                print(f"Warning:not cache ids:{remain_object_ids}")

    @staticmethod
    def list_base64(data: list):
        return base64.b64encode(bytes(data)).decode("ascii")

    def execute_transaction(self,
                            tx_bytes,
                            sig_scheme="ED25519",
                            request_type="WaitForLocalExecution",
                            index_object: bool = True
                            ) -> dict:
        """

        :param index_object:
        :param tx_bytes:
        :param sig_scheme:
        :param request_type:
            Execute the transaction and wait for results if desired. Request types:
            1. ImmediateReturn: immediately returns a response to client without waiting for any execution results.
            Note the transaction may fail without being noticed by client in this mode. After getting the response,
            the client may poll the node to check the result of the transaction.
            2. WaitForTxCert: waits for TransactionCertificate and then return to client.
            3. WaitForEffectsCert: waits for TransactionEffectsCert and then return to client.
            This mode is a proxy for transaction finality.
            4. WaitForLocalExecution: waits for TransactionEffectsCert and make sure the node executed the transaction
            locally before returning the client. The local execution makes sure this node is aware of this transaction
            when client fires subsequent queries. However if the node fails to execute the transaction locally in a
            timely manner, a bool type in the response is set to false to indicated the case
        :return:
        """
        assert sig_scheme == "ED25519", "Only support ED25519"
        SIGNATURE_SCHEME_TO_FLAG = {
            "ED25519": 0,
            "Secp256k1": 1
        }
        serialized_sig = [SIGNATURE_SCHEME_TO_FLAG[sig_scheme]]
        serialized_sig.extend(list(self.account.sign(tx_bytes).get_bytes()))
        serialized_sig.extend(list(self.account.public_key().get_bytes()))
        serialized_sig_base64 = self.list_base64(serialized_sig)

        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_executeTransactionSerializedSig",
                "params": [
                    tx_bytes,
                    serialized_sig_base64,
                    request_type
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        result = self.format_result(result)
        try:
            transactions = result["EffectsCert"]["certificate"]["data"]["transactions"][0]["Call"]
            module = transactions["module"]
            function = transactions["function"]
        except:
            module = None
            function = None
        try:
            if result["EffectsCert"]["effects"]["effects"]["status"]["status"] != "success":
                pprint(result)
            assert result["EffectsCert"]["effects"]["effects"]["status"]["status"] == "success"
            result = result["EffectsCert"]["effects"]["effects"]
            if index_object:
                self.add_details(result)
            if module is None:
                print(f"Execute success, transactionDigest: {result['transactionDigest']}")
            else:
                print(f"Execute {module}::{function} success, transactionDigest: {result['transactionDigest']}")
            return result
        except:
            traceback.print_exc()
            return result

    @staticmethod
    def slice_data(data: list, num: int) -> List[list]:
        result = {}
        for i in range(len(data)):
            index = i % num
            if index not in result:
                result[index] = []
            result[index].append(data[i])
        return [v for v in result.values()]

    def get_objects(self, object_ids: List[str]):

        result = {}

        def worker(d: List[str]):
            for v in d:
                detail = self.get_object(v)
                if "data" in detail and "disassembled" in detail["data"]:
                    del detail["data"]["disassembled"]
                result[v] = detail

        num = 20

        engine = ThreadExecutor(executor=num)

        split_data = self.slice_data(object_ids, num)
        workers = [functools.partial(worker, m) for m in split_data]
        engine.run(workers)
        return result

    def get_object(self, object_id: str):
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getObject",
                "params": [
                    object_id
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        try:
            data = result["details"]
            if "status" in result:
                data["status"] = result["status"]
            return data
        except:
            return result

    def get_object_by_object(self, object_id: str):
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getObjectsOwnedByObject",
                "params": [
                    object_id
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        try:
            data = result["details"]
            if "status" in result:
                data["status"] = result["status"]
            return data
        except:
            return result

    def get_object_by_address(self, addr: str):
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getObjectsOwnedByAddress",
                "params": [
                    addr
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        try:
            data = result["details"]
            if "status" in result:
                data["status"] = result["status"]
            return data
        except:
            return result

    def get_abis(self):
        if self.package_id is None:
            return
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getNormalizedMoveModulesByPackage",
                "params": [
                    self.package_id
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        for module_name in result:
            for struct_name in result[module_name].get("structs", dict()):
                if len(result[module_name]["structs"][struct_name].get("type_parameters", [])):
                    continue
                object_type = ObjectType.from_type(f"{self.package_id}::{module_name}::{struct_name}")
                object_type.package_name = self.package_name
                insert_cache(object_type, None)
                attr_list = [module_name, struct_name]
                if len(attr_list):
                    final_object = self
                    for attr in attr_list[:-1]:
                        if hasattr(final_object, attr):
                            final_object = getattr(final_object, attr)
                        else:
                            ob = type(f"{attr}_{id(self)}", (object,), dict())()
                            setattr(final_object, attr, ob)
                            final_object = ob
                    struct_names = object_type.normal_struct()
                    if len(struct_names) == 0:
                        break
                    # correct name
                    attr = struct_names[0]
                    if self.account.account_address not in CacheObject[object_type]:
                        if "Shared" in CacheObject[object_type] and len(CacheObject[object_type]["Shared"]):
                            init_acc_data = copy.deepcopy(CacheObject[object_type]["Shared"])
                        else:
                            init_acc_data = []
                        CacheObject[object_type][self.account.account_address] = init_acc_data
                    setattr(final_object, attr, CacheObject[object_type][self.account.account_address])
            for func_name in result[module_name].get("exposed_functions", dict()):
                abi = result[module_name]["exposed_functions"][func_name]
                abi["module_name"] = module_name
                abi["func_name"] = func_name
                self.abis[f"{module_name}::{func_name}"] = abi
                attr_list = [module_name, func_name]
                if len(attr_list):
                    final_object = self
                    for attr in attr_list[:-1]:
                        if hasattr(final_object, attr):
                            final_object = getattr(final_object, attr)
                        else:
                            ob = type(f"{attr}_{id(self)}", (object,), dict())()
                            setattr(final_object, attr, ob)
                            final_object = ob
                    func = functools.partial(self.submit_transaction, abi)
                    setattr(func, "simulate", functools.partial(self.simulate_transaction, abi))
                    setattr(func, "inspect_call", functools.partial(self.dev_inspect_move_call, abi))
                    setattr(final_object, attr_list[-1], func)

    def __getitem__(self, key):
        assert key in self.abis, f"key not found in abi"
        return functools.partial(self.submit_transaction, self.abis[key])

    @staticmethod
    def judge_ctx(param) -> bool:
        if not isinstance(param, dict):
            return False
        if "MutableReference" in param:
            final_arg = param["MutableReference"].get("Struct", dict())
        elif "Reference" in param:
            final_arg = param["Reference"].get("Struct", dict())
        else:
            final_arg = {}
        if final_arg.get("address", None) == "0x2" \
                and final_arg.get("module", None) == "tx_context" \
                and final_arg.get("name", None) == "TxContext":
            return True
        else:
            return False

    @classmethod
    def cascade_type_arguments(cls, data, ty_args: list = None) -> str:
        if ty_args is None:
            ty_args = []
        if len(data) == 0:
            return ""
        output = "<"
        for k, v in enumerate(data):
            if k != 0:
                output += ","
            if "TypeParameter" in v:
                data = ty_args[v["TypeParameter"]]
            else:
                data = "::".join([v["Struct"]["address"], v["Struct"]["module"], v["Struct"]["name"]])
                if len(v["Struct"]["type_arguments"]):
                    data += cls.cascade_type_arguments(v["Struct"]["type_arguments"], ty_args)
            output += data
        output += ">"
        return output

    @classmethod
    def generate_object_type(cls, param: str, ty_args: list = None) -> ObjectType:
        if not isinstance(param, dict):
            return None
        if "Reference" in param:
            final_arg = param["Reference"]
        elif "MutableReference" in param:
            final_arg = param["MutableReference"]
        elif "Struct" in param:
            final_arg = param
        else:
            return None

        if "Struct" in final_arg:
            try:
                output = cls.cascade_type_arguments(final_arg["Struct"]["type_arguments"], ty_args)
            except:
                return None
            output = f'{final_arg["Struct"]["address"]}::' \
                     f'{final_arg["Struct"]["module"]}::' \
                     f'{final_arg["Struct"]["name"]}{output}'
            return ObjectType.from_type(output)
        else:
            return None

    @classmethod
    def judge_coin(cls, param: str, ty_args: list = None) -> ObjectType:
        data = cls.generate_object_type(param, ty_args)
        if isinstance(data, ObjectType) \
                and data.package_id == "0x2" \
                and data.module_name == "coin" \
                and data.struct_name.startswith("Coin"):
            return data
        else:
            return None

    def get_coin_info(self, object_ids: list) -> Dict[str, Coin]:
        result = self.get_objects(object_ids)
        coin_info: Dict[str, Coin] = {}
        for k in result:
            if not result[k].get("status", None) == "Exists":
                continue
            owner_info = result[k]["owner"]
            if "Shared" in owner_info:
                owner = "Shared"
            else:
                try:
                    owner = owner_info["AddressOwner"]
                except:
                    continue
            coin_info[k] = Coin(k, owner, int(result[k]["data"]["fields"]["balance"]))
        return coin_info

    @classmethod
    def normal_float_list(cls, data: list):
        for k in range(len(data)):
            if isinstance(data[k], float):
                assert float(int(data[k])) == data[k], f"{data[k]} must int"
                data[k] = int(data[k])
            elif isinstance(data[k], list):
                cls.normal_float_list(data[k])

    def __refresh_coin(self, is_coin: ObjectType):
        coin_info = self.get_coin_info(CacheObject[is_coin][self.account.account_address])
        coin_info = {k: coin_info[k] for k in coin_info if coin_info[k].owner == self.account.account_address}
        CacheObject[is_coin][self.account.account_address] = sorted(coin_info.keys(),
                                                                    key=lambda x: coin_info[x].balance)[::-1]
        return coin_info

    def refresh_coin(self, coin_type: str):
        """
        :param coin_type: 0x2::sui::SUI
        """
        is_coin = ObjectType.from_type(f'0x2::coin::Coin<{coin_type}>')
        self.__refresh_coin(is_coin)

    def check_args(
            self,
            abi: dict,
            param_args: list,
            ty_args: List[str] = None
    ):
        param_args = list(param_args)
        self.normal_float_list(param_args)

        if ty_args is None:
            ty_args = []
        assert isinstance(list(ty_args), list) and len(
            abi["type_parameters"]) == len(ty_args), f"ty_args error: {abi['type_parameters']}"
        if len(abi["parameters"]) and self.judge_ctx(abi["parameters"][-1]):
            assert len(param_args) == len(abi["parameters"]) - 1, f'param_args error: {abi["parameters"]}'
        else:
            assert len(param_args) == len(abi["parameters"]), f'param_args error: {abi["parameters"]}'

        return param_args, ty_args

    def dev_inspect_move_call(
            self,
            abi: dict,
            *param_args,
            ty_args: List[str] = None
    ):
        param_args, ty_args = self.check_args(abi, param_args, ty_args)

        for k in range(len(param_args)):
            if abi["parameters"][k] in ["U64", "U128", "U256"]:
                param_args[k] = str(param_args[k])

        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_devInspectMoveCall",
                "params": [
                    self.account.account_address,
                    self.package_id,
                    abi["module_name"],
                    abi["func_name"],
                    ty_args,
                    param_args,
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]["results"]
        return result

    def construct_transaction(
            self,
            abi: dict,
            param_args: list,
            ty_args: List[str] = None,
            gas_budget=10000,
    ):
        param_args, ty_args = self.check_args(abi, param_args, ty_args)

        normal_coin: List[ObjectType] = []

        for k in range(len(param_args)):
            is_coin = self.judge_coin(abi["parameters"][k], ty_args)
            if is_coin is None:
                continue
            if not isinstance(param_args[k], int):
                continue
            assert len(CacheObject[is_coin][self.account.account_address]), f"Not found coin"

            normal_coin.append(is_coin)

            # merge
            self.__refresh_coin(is_coin)

            if len(CacheObject[is_coin][self.account.account_address]) > 1:
                if str(is_coin) == "0x2::coin::Coin<0x2::sui::SUI>":
                    self.pay_all_sui(
                        self.account.account_address,
                        gas_budget
                    )
                else:
                    self.merge_coins(CacheObject[is_coin][self.account.account_address], gas_budget)

            # split
            coin_info = self.__refresh_coin(is_coin)
            first_object_id = CacheObject[is_coin][self.account.account_address][0]
            first_coin_info = coin_info[first_object_id]
            assert first_coin_info.balance >= param_args[k] + gas_budget, \
                f'Balance not enough: ' \
                f'{first_coin_info.balance} < ' \
                f'{param_args[k]}'
            split_amounts = [param_args[k]]
            if str(is_coin) == "0x2::coin::Coin<0x2::sui::SUI>":
                self.pay_sui(
                    [first_object_id],
                    split_amounts,
                    [self.account.account_address] * len(split_amounts),
                    gas_budget)
            else:
                self.split_coin(
                    [first_object_id],
                    split_amounts
                )

            # find
            coin_info = self.__refresh_coin(is_coin)
            for oid in coin_info:
                if coin_info[oid].balance == param_args[k]:
                    param_args[k] = oid
                    break
            assert not isinstance(param_args[k], int), "Fail split amount"

        for k in range(len(param_args)):
            if abi["parameters"][k] in ["U64", "U128", "U256"]:
                param_args[k] = str(param_args[k])

        # print(f'\nConstruct transaction {abi["module_name"]}::{abi["func_name"]}')
        object_ids = self.get_coins(self.account.account_address, "0x2::sui::SUI")
        gas_object = max(list(object_ids.keys()), key=lambda x: object_ids[x])
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_moveCall",
                "params": [
                    self.account.account_address,
                    self.package_id,
                    abi["module_name"],
                    abi["func_name"],
                    ty_args,
                    param_args,
                    gas_object,
                    gas_budget
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return result

    @validator_retry
    def submit_transaction(
            self,
            abi: dict,
            *param_args,
            ty_args: List[str] = None,
            gas_budget=10000,
            is_merge_sui=True
    ) -> dict:
        """
        {
          'is_entry': True,
          "module_name": "main",
          "func_name": "set_m",
          'parameters': [{'MutableReference': {'Struct': {'address': '0x22f59a7d8680232c52e2203475382532630989a4',
                                                          'module': 'main',
                                                          'name': 'Hello',
                                                          'type_arguments': []}}},
                         {'Reference': {'Struct': {'address': '0x22f59a7d8680232c52e2203475382532630989a4',
                                                   'module': 'main',
                                                   'name': 'Hello',
                                                   'type_arguments': []}}},
                         {'Struct': {'address': '0x22f59a7d8680232c52e2203475382532630989a4',
                                     'module': 'main',
                                     'name': 'Hello',
                                     'type_arguments': []}},
                         'U8',
                         {'MutableReference': {'Struct': {'address': '0x2',
                                                          'module': 'tx_context',
                                                          'name': 'TxContext',
                                                          'type_arguments': []}}}],
          'return_': [],
          'type_parameters': [{'abilities': []},
                              {'abilities': []}],
          'visibility': 'Public'}
        :param is_merge_sui:
        :param param_args:
        :param abi:
        :param ty_args:
        :param gas_budget:
        :return:
        """
        # Merge sui
        if is_merge_sui:
            self.pay_all_sui(self.account.account_address)

        result = self.construct_transaction(abi, param_args, ty_args, gas_budget)
        # Simulate before execute
        self.dry_run_transaction(result["txBytes"])
        # Execute
        print(f'\nExecute transaction {abi["module_name"]}::{abi["func_name"]}, waiting...')
        return self.execute_transaction(result["txBytes"])

    def simulate_transaction(
            self,
            abi: dict,
            *param_args,
            ty_args: List[str] = None,
            gas_budget=10000,
    ) -> Union[list | int]:
        """
        return_types: storage|gas
            storage: return storage changes
            gas: return gas
        """
        result = self.construct_transaction(abi, param_args, ty_args, gas_budget)
        print(f'\nSimulate transaction {abi["module_name"]}::{abi["func_name"]}')
        return self.dry_run_transaction(result["txBytes"])

    @validator_retry
    def pay_all_sui(self, recipient: str = None, gas_budget=1000):
        object_ids = self.get_coins(self.account.account_address, "0x2::sui::SUI")
        input_coins = sorted(list(object_ids.keys()), key=lambda x: object_ids[x])[::-1]
        if recipient is None:
            recipient = self.account.account_address
        if len(input_coins) < 2 and recipient == self.account.account_address:
            return
        print(f'\nExecute sui_payAllSui...')
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_payAllSui",
                "params": [
                    self.account.account_address,
                    input_coins,
                    recipient,
                    gas_budget
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return self.execute_transaction(result["txBytes"])

    @validator_retry
    def pay_sui(self, input_coins: list, amounts: list, recipients: list = None, gas_budget=10000):
        if recipients is None:
            recipients = self.account.account_address
        print(f'\nExecute sui_paySui...')
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_paySui",
                "params": [
                    self.account.account_address,
                    input_coins,
                    recipients,
                    amounts,
                    gas_budget
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return self.execute_transaction(result["txBytes"])

    @validator_retry
    def pay(self, input_coins: list, amounts: list, recipients: list = None, gas_budget=10000):
        if recipients is None:
            recipients = self.account.account_address
        print(f'\nExecute sui_pay...')
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_pay",
                "params": [
                    self.account.account_address,
                    input_coins,
                    recipients,
                    amounts,
                    None,
                    gas_budget
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return self.execute_transaction(result["txBytes"])

    @validator_retry
    def merge_coins(self, input_coins: list, gas_budget=10000):
        assert len(input_coins) >= 2
        print(f'\nExecute sui_mergeCoins...')
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_mergeCoins",
                "params": [
                    self.account.account_address,
                    input_coins[0],
                    input_coins[1:],
                    None,
                    gas_budget
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return self.execute_transaction(result["txBytes"])

    @validator_retry
    def split_coin(self, input_coin: str, split_amounts: list, gas_budget=10000):
        print(f'\nExecute sui_splitCoin...')
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_splitCoin",
                "params": [
                    self.account.account_address,
                    input_coin,
                    split_amounts,
                    None,
                    gas_budget
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return self.execute_transaction(result["txBytes"])

    def get_coins(self, addr: str, coin_type: str) -> dict:
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getCoins",
                "params": [
                    addr,
                    coin_type
                ]
            },
        )
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        object_ids = {v["coinObjectId"]: v["balance"] for v in result["result"]["data"]}
        return object_ids

    def get_dynamic_field(self, object_id: str) -> List[SuiDynamicFiled]:
        data = self.get_object_by_object(object_id)
        oids = []
        for v in data:
            oids.append(v["objectId"])
        if len(oids) == 0:
            return []
        output = []
        info = self.get_objects(oids)
        for k in info:
            output.append(SuiDynamicFiled(owner=object_id,
                                          uid=info[k]["data"]["fields"]["id"]["id"],
                                          name=info[k]["data"]["fields"]["name"],
                                          value=info[k]["data"]["fields"]["value"]["fields"]
                                          if (isinstance(info[k]["data"]["fields"]["value"], dict) and "fields" in
                                              info[k]["data"]["fields"]["value"])
                                          else info[k]["data"]["fields"]["value"],
                                          ty=info[k]["data"]["type"]
                                          ))
        return output

    def get_table_item(self, object_id: str) -> List[SuiDynamicFiled]:
        return self.get_dynamic_field(object_id)

    def get_bag_item(self, object_id: str) -> List[SuiDynamicFiled]:
        return self.get_dynamic_field(object_id)

    @staticmethod
    def normal_object_info(data):
        return data.get("data", dict()).get("fields", dict())

    def nest_process_table(self, basic_info: dict):
        if not isinstance(basic_info, dict):
            return
        table_keys = []
        for k in basic_info:
            if not (isinstance(basic_info[k], dict) and "type" in basic_info[k] and "fields" in basic_info[k]):
                continue
            object_type = ObjectType.from_type(basic_info[k]["type"])
            if object_type.package_id == "0x2":
                if object_type.module_name == "table" and object_type.struct_name.startswith("Table"):
                    tid = basic_info[k]["fields"]["id"]["id"]
                    basic_info[k] = self.get_table_item(tid)
                    table_keys.append(k)
                elif object_type.module_name == "bag" and object_type.struct_name.startswith("Bag"):
                    tid = basic_info[k]["fields"]["id"]["id"]
                    basic_info[k] = self.get_bag_item(tid)
                    table_keys.append(k)
            if "fields" in basic_info[k]:
                self.nest_process_table(basic_info[k]["fields"])
                basic_info[k] = basic_info[k]["fields"]

        # nested processing table info's value
        for k in table_keys:
            for i in range(len(basic_info[k])):
                data: SuiDynamicFiled = basic_info[k][i]
                self.nest_process_table(data.value)

    def normal_detail(self, data):
        if isinstance(data, dict):
            if "type" in data and "fields" in data:
                d = data["fields"]
                del data["fields"]
                del data["type"]
                data.update(d)
            for k in list(data.keys()):
                self.normal_detail(data[k])
        elif isinstance(data, list):
            for i in range(len(data)):
                self.normal_detail(data[i])
        elif isinstance(data, SuiDynamicFiled):
            self.normal_detail(data.name)
            self.normal_detail(data.value)

    def get_object_with_super_detail(self, object_id):
        basic_info = self.normal_object_info(self.get_object(object_id))

        self.nest_process_table(basic_info)

        dynamic_info = self.get_dynamic_field(object_id)
        basic_info["dynamic_field"] = dynamic_info
        self.normal_detail(basic_info)
        return basic_info
