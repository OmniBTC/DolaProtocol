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

from account import Account

import yaml
import toml

from parallelism import ThreadExecutor
from sui_brownie.sui_client import SuiClient

_load_project = []


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
            package_path: Union[Path, str] = None,
    ):
        assert len(_load_project) > 0, "Project not init"
        self.project: SuiProject = _load_project[0]
        self.package_id = package_id
        self.package_path = package_path

        self.abi = {}

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
        self.cache_objects = DefaultDict(DefaultDict([]))

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
        if not self.cache_file.parent.exists():
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)

        if not self.cache_file.exists():
            return

        with open(str(self.cache_file), "r") as f:
            try:
                data = json.load(f)
            except Exception as e:
                print(f"Warning: read cache occurs {e}")
                return

        for sui_object_type in data:
            try:
                object_type = SuiObject.from_type(sui_object_type)
                for v in data[sui_object_type]:
                    for v1 in data[sui_object_type][v]:
                        pass
                        # insert_cache(object_type, v1, v)
            except:
                for v in data[sui_object_type]:
                    for v1 in data[sui_object_type][v]:
                        pass
                        # insert_package(sui_object_type, v1)

    def add_package(self, package: SuiPackage):
        self.packages[package.package_id] = package
