from __future__ import annotations

import base64
import copy
import functools
import json
import multiprocessing
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

from account import Account
from atomicwrites import atomic_write

import yaml
import toml

from parallelism import ThreadExecutor
from sui_brownie.sui_client import SuiClient

_load_project = []

_cache_file_lock = multiprocessing.Lock()


class AttributeDict(dict):
    def __getattr__(self, item):
        return self[item]


class DefaultDict(dict):
    def __init__(self, default=None):
        self.default = default
        super().__init__()

    def __getitem__(self, item):
        if item not in self:
            super(DefaultDict, self).__setitem__(item, copy.deepcopy(self.default))
        return super(DefaultDict, self).__getitem__(item)

    def __len__(self):
        return len(self.keys())

    def keys(self):
        data = list(super().keys())
        if "default" in data:
            del data["default"]
        return data


class NonDupList(list):
    def append(self, __object) -> None:
        if __object not in self:
            super(NonDupList, self).append(__object)


class MoveToml:
    """Easy recovery after package replacement address"""

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

    def get(self, k1, k2):
        return self.data.get(k1, k2)

    def keys(self):
        return self.data.keys()


class SuiObject:
    __single_object: Dict[str, SuiObject] = dict()

    def __init__(self,
                 package_id: str,
                 module_name: str,
                 struct_name: str
                 ):
        self.package_id = package_id
        self.module_name = module_name
        self.struct_name = struct_name
        self.package_name = ""
        assert str(self) not in self.__single_object, f"{package_id} has exist, use 'from_data' create"

    @classmethod
    def from_data(
            cls,
            package_id: str,
            module_name: str,
            struct_name: str
    ) -> SuiObject:
        data = f"{package_id}::{module_name}::{struct_name}"
        if data not in cls.__single_object:
            cls.__single_object[data] = SuiObject(package_id, module_name, struct_name)
        return cls.__single_object[data]

    @classmethod
    def from_type(cls, data: str) -> SuiObject:
        """
        :param data:
            0xb5189942a34446f1d037b446df717987e20a5717::main1::Hello
        :return:
        """
        data = cls.normal_type(data)
        data = data.split("::")
        result = data[:2]
        result.append("::".join(data[2:]))

        return cls.from_data(*result)

    @staticmethod
    def normal_package_id(package_id) -> str:
        """
        0x2 -> 0x0000000000000000000000000000000000000000000000000000000000000002
        :param package_id:
        :return:
        """
        if package_id == "0x2":
            return package_id
        if package_id[:2] == "0x" and len(package_id[2:]) < 64:
            package_id = f"0x{'0' * (64 - len(package_id[2:]))}{package_id[2:]}"
        return package_id

    @classmethod
    def normal_type(cls, data: str):
        """
        0xb5189942a34446f1d037b446df717987e20a5717::main1::Hello -> SuiObject
        :param data:
        :return:
        """
        data = data.split("::")
        for k in range(len(data)):
            index = data[k].find("0x")
            data[k] = data[k][:index] + cls.normal_package_id(data[k][index:])
        return "::".join(data)

    @staticmethod
    def is_sui_object(data: str) -> bool:
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
        """
        0xb5189942a34446f1d037b446df717987e20a5717::main1::Hello -> [Hello]
        0xb5189942a34446f1d037b446df717987e20a5717::main1::Hello<T> -> [Hello, T]
        :return:
        """
        if self.struct_name is None:
            return []
        elif self.struct_name[-1] == ">":
            index = self.struct_name.find("<")
            return [self.struct_name[:index], self.struct_name[index + 1:-1]]
        else:
            return [self.struct_name]


class MoveToml:
    """Easy recovery after package replacement address"""

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


class SuiPackage:
    def __init__(
            self,
            package_id: str = None,
            package_name: str = None,
            package_path: Union[Path, str] = None,
    ):
        assert len(_load_project) > 0, "Project not init"
        self.project: SuiProject = _load_project[0]
        assert package_id is not None or package_path is not None
        assert package_path is None and package_name is not None, f"Package path is none, set package name"
        self.package_id = package_id
        self.package_name = package_name

        self.package_path = package_path
        # package_path is not none
        self.move_toml: MoveToml = MoveToml(str(self.package_path)) if self.package_path is not None else None
        if self.package_name is None and self.move_toml is not None:
            self.package_name = self.move_toml.get("package", "name")

        # module name -> struct -> SuiObjectType
        #             -> func  -> () : call transaction
        #                      -> simulate : simulate transaction
        #                      -> inspect : inspect value
        # Record package struct and func abi
        self.modules = DefaultDict({})

        if self.package_id is not None:
            self.update_abi()

    def __getattribute__(self, item):
        try:
            return object.__getattribute__(self, item)
        except Exception as e:
            if item in self.modules:
                return self.modules[item]
            else:
                raise e

    def load_package(self):
        if self.package_path is None:
            self.package_path = self.project.project_path
        elif isinstance(self.package_path, str):
            self.package_path = Path(self.package_path)
        else:
            self.package_path = self.package_path

    def update_abi(self):
        if self.package_id is None:
            return

        result = self.project.client.sui_getNormalizedMoveModulesByPackage(self.package_id)

        for module_name in result:
            # Update
            for struct_name in result[module_name].get("structs", dict()):
                # refuse process include type param object
                if len(result[module_name]["structs"][struct_name].get("type_parameters", [])):
                    continue
                object_type = SuiObject.from_type(f"{self.package_id}::{module_name}::{struct_name}")
                object_type.package_name = self.package_name
                self.modules[module_name][struct_name] = object_type
            for func_name in result[module_name].get("exposed_functions", dict()):
                abi = result[module_name]["exposed_functions"][func_name]
                abi["module_name"] = module_name
                abi["func_name"] = func_name
                self.modules[module_name][func_name] = abi
                self.abi[f"{module_name}::{func_name}"] = abi

    # ####### Publish

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
                        dep_move_toml = SuiPackage(package_path=local_path)
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
                        dep_move_toml = SuiPackage(package_path=remote_path)
                        dep_move_toml.replace_addresses(replace_address, output)

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
                cmd = f"sui client --client.config {cof.file.absolute()} publish " \
                      f"--skip-dependency-verification --gas-budget {gas_budget} " \
                      f"--abi --json {self.package_path.absolute()}"
                with os.popen(cmd) as f:
                    result = f.read()
                try:
                    result = json.loads(result[result.find("{"):])
                    result = self.format_result(result)
                except:
                    pprint(f"Publish error:\n{result}")
                    return
                self.update_object_index(result.get("effects", dict()))
                for d in result.get("effects").get("created", []):
                    if "data" in d and "dataType" in d["data"]:
                        if d["data"]["dataType"] == "package":
                            self.package_id = d["reference"]["objectId"]
                            self.project.add_package(self)
                            self.update_abi()
            pprint(result)
            print("-" * (100 + len(view)))
            print("\n")
            for k in replace_tomls:
                replace_tomls[k].restore()
        except Exception as e:
            for k in replace_tomls:
                replace_tomls[k].restore()
            assert False, e
        return result

    # ###### Call
    def update_object_index(self, result):
        """
        Update Object cache after contract deployment and transaction execution
        :param result: effects
            {
              "messageVersion": "v1",
              "status": {
                "status": "success"
              },
              "mutated": [
                {
                  "owner": {
                    "AddressOwner": "0x61fbb5b4f342a40bdbf87fe4a946b9e38d18cf8ffc7b0000b975175c7b6a9576"
                  },
                  "reference": {
                    "objectId": "0xe8d8c7ce863f313da3dbd92a83ef26d128b88fe66bf26e0e0d09cdaf727d1d84",
                    "version": 2,
                    "digest": "EnRQXe1hDGAJCFyF2ds2GmPHdvf9V6yxf24LisEsDkYt"
                  }
                }
              ]
            }
        :return:
        """
        sui_object_ids = []
        for k in ["created", "mutated"]:
            for d in result.get(k, dict()):
                if "reference" in d and "objectId" in d["reference"]:
                    sui_object_ids.append(d["reference"]["objectId"])
        if len(sui_object_ids):
            sui_object_infos = self.project.client.sui_multiGetObjects(sui_object_ids, {
                "showType": True,
                "showOwner": True,
                "showPreviousTransaction": False,
                "showDisplay": False,
                "showContent": False,
                "showBcs": False,
                "showStorageRebate": False
            })
            for sui_object_info in sui_object_infos:
                if "error" in sui_object_info:
                    continue
                sui_object_id = sui_object_info["data"]["objectId"]
                if sui_object_info["data"]["type"] == "package":
                    continue
                else:
                    sui_object = SuiObject.from_type(sui_object_info["data"]["type"])
                    if "Shared" in sui_object_info["data"]["owner"]:
                        self.project.add_object_to_cache(sui_object, "Shared", sui_object_id)
                    elif "AddressOwner" in sui_object_info["data"]["owner"]:
                        owner = sui_object_info["data"]["owner"]["AddressOwner"]
                        self.project.add_object_to_cache(sui_object, owner, sui_object_id)


class SuiProject:
    def __init__(
            self,
            project_path: Union[Path, str] = Path.cwd(),
            network: str = "sui-testnet"
    ):
        self.project_path = project_path
        self.network = network

        self.config = {}
        self.network_config = {}
        self.client: SuiClient = None
        self.accounts: Dict[str, Account] = {}
        self.packages: Dict[str, SuiPackage] = {}

        self.cache_file = Path(os.environ.get('HOME')).joinpath(".sui-brownie").joinpath("objects.json")
        self.cache_objects: Dict[Union[SuiObject, str], Dict[str, list]] = DefaultDict(DefaultDict(NonDupList))

        self.load_config()

    def load_config(self):
        # Check path
        if isinstance(self.project_path, Path):
            self.project_path = self.project_path
        else:
            self.project_path = Path(self.project_path)
        assert self.project_path.joinpath("brownie-config.yaml").exists(), "Project not found brownie-config.yaml"

        # Read config
        with self.project_path.joinpath("brownie-config.yaml").open() as fp:
            self.config = yaml.safe_load(fp)
        assert "networks" in self.config, f"networks not found in brownie-config.yaml"
        assert self.network in self.config["networks"], f"{self.network} not found in brownie-config.yaml"
        self.network_config = self.config["networks"][self.network]

        # Read count
        env_file = self.config["dotenv"] if "dotenv" in self.config else ".env"
        env = dotenv_values(self.project_path.joinpath(env_file))
        assert "sui_wallets" in self.config, "Unassigned activation accounts"
        assert "from_mnemonic" in self.config["sui_wallets"], "Wallet config format error"
        for account_name, env_name in self.config["sui_wallets"]["from_mnemonic"].items():
            env_name = env_name.replace("$", "").replace("{", "").replace("}", "")
            assert env_name in env, f"{env_name} env not exist"
            self.accounts[account_name] = env[env_name]

        # Create client
        assert "node_url" in self.network_config, "Endpoint not config"
        self.client = SuiClient(base_url=self.network_config["node_url"], timeout=30)

    def reload_cache(self):
        data = self.read_cache()
        for k1 in data:
            try:
                sui_object = SuiObject.from_type(k1)
                for k2 in data[k1]:
                    for object_id in data[k1][k2]:
                        self.add_object_to_cache(sui_object, k2, object_id, persist=False)
            except:
                for k2 in data[k1]:
                    for package_id in data[k1][k2]:
                        self.add_package_to_cache(k1, package_id, persist=False)

    def read_cache(self):
        if not self.cache_file.exists():
            return {}

        with open(str(self.cache_file), "r") as f:
            try:
                data = json.load(f)
            except Exception as e:
                print(f"Warning: read cache occurs {e}")
                return {}
        return data

    def write_cache(self):
        if not self.cache_file.parent.exists():
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)

        def write_cache_worker():
            output = DefaultDict({})
            for k1 in self.cache_objects:
                for k2 in self.cache_objects[k1]:
                    output[str(k1)][str(k2)] = self.cache_objects[k1][k2]
            while True:
                try:
                    _cache_file_lock.acquire(timeout=10)
                    with atomic_write(str(self.cache_file), overwrite=True) as f:
                        json.dump(output, f, indent=1, sort_keys=True)
                    _cache_file_lock.release()
                    break
                except Exception as e:
                    print(f"Write cache fail, err:{e}")
                    time.sleep(1)

        pt = ThreadExecutor(executor=1, mode="all")
        pt.run([write_cache_worker])

    def add_object_to_cache(self, sui_object: SuiObject, owner, sui_object_id, persist=True):
        self.cache_objects[sui_object][owner].append(sui_object_id)
        if persist:
            self.write_cache()

    def add_package_to_cache(self, package_name, package_id, persist=True):
        assert package_name is not None, f"{package_id} name is none"
        self.cache_objects[package_name]["Shared"].append(package_id)
        if persist:
            self.write_cache()

    def add_package(self, package: SuiPackage):
        self.packages[package.package_id] = package
        self.add_package_to_cache(package.package_name, package.package_id)
