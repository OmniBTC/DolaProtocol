from __future__ import annotations

import base64
import functools
import json
import os
import time
import traceback
from collections import OrderedDict
from pathlib import Path
from typing import Union, List, Dict
from pprint import pprint
from retrying import retry

import httpx
from dotenv import load_dotenv

from account import Account

import yaml
import toml

from Parallelism import ThreadExecutor


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

    @classmethod
    def from_type(cls, data: str) -> ObjectType:
        """
        :param data:
            0xb5189942a34446f1d037b446df717987e20a5717::main1::Hello
        :return:
        """
        data = data.split("::")
        result = data[:2]
        result.append("::".join(data[2:]))
        return cls.from_data(*result)

    def __repr__(self):
        return self.__str__()

    def __str__(self):
        return f"{self.package_id}::{self.module_name}::{self.struct_name}"

    def __hash__(self):
        return hash(str(self))


CacheObject: Dict[ObjectType, list] = OrderedDict()


def persist_cache(cache_file):
    data = {}
    for k in CacheObject:
        if len(CacheObject[k]):
            data[str(k)] = CacheObject[k]
    if len(data) == 0:
        return
    pt = ThreadExecutor(executor=1, mode="all")

    def worker():
        with open(str(cache_file), "w") as f:
            json.dump(data, f, indent=4, sort_keys=True)

    pt.run([worker])


def reload_cache(cache_file):
    with open(str(cache_file), "r") as f:
        try:
            data = json.load(f)
        except:
            data = {}
        for k in data:
            object_type = ObjectType.from_type(k)
            if object_type in CacheObject:
                for v in CacheObject[object_type]:
                    data[k].append(v)
            CacheObject[ObjectType.from_type(k)] = data[k]


def insert_cache(object_type: ObjectType, object_id: str = None):
    if object_type not in CacheObject:
        CacheObject[object_type] = [object_id] if object_id is not None else []
        final_object = CacheObject
        attr_list = [object_type.module_name, object_type.struct_name]
        for k, attr in enumerate(attr_list):
            if hasattr(final_object, attr):
                final_object = getattr(final_object, attr)
            else:
                if k == len(attr_list) - 1:
                    ob = dict()
                else:
                    ob = type(f"CacheObject_{object_type.module_name}", (object,), dict())()
                setattr(final_object, attr, ob)
                final_object = ob
            if k == len(attr_list) - 1 and object_type not in final_object:
                final_object[object_type] = CacheObject[object_type]
    elif object_id is not None and object_id not in CacheObject[object_type]:
        CacheObject[object_type].append(object_id)


class ApiError(Exception):
    """Error thrown when the API returns >= 400"""

    def __init__(self, message, status_code):
        # Call the base class constructor with the parameters it needs
        super().__init__(message)
        self.status_code = status_code


class SuiPackage:
    def __init__(self,
                 brownie_config: Union[Path, str] = Path.cwd(),
                 network: str = "sui-devnet",
                 is_compile: bool = True,
                 package_id: str = None,
                 package_path: Union[Path, str] = None
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

        # # # # # cache file
        cache_dir = self.brownie_config.joinpath(".cache")
        if not cache_dir.exists():
            cache_dir.mkdir()
        self.cache_file = cache_dir.joinpath("objects.json")

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
            load_dotenv(self.brownie_config.joinpath(self.config["dotenv"]))
            self.private_key = os.getenv("PRIVATE_KEY")
            self.mnemonic = os.getenv("MNEMONIC")
            if self.private_key is not None:
                self.account = Account.load_key(self.private_key)
            elif self.mnemonic is not None:
                self.account = Account.load_mnemonic(self.mnemonic)
            else:
                raise EnvironmentError
        except Exception as e:
            raise e

        # current aptos network config
        self.network_config = self.config["networks"][network]
        self.base_url = self.config["networks"][network]["node_url"]
        self.client = httpx.Client()

        # # # # # load move toml
        assert self.package_path.joinpath(
            "Move.toml").exists(), "Move.toml not found"
        self.move_path = self.package_path.joinpath("Move.toml")
        self.move_toml = {}
        with self.move_path.open() as fp:
            self.move_toml = toml.load(fp)
        self.package_name = self.move_toml["package"]["name"]

        # # # # # Replace address
        self.replace_address = ""
        has_replace = {}
        if "addresses" in self.move_toml:
            if "replace_address" in self.network_config:
                for k in self.network_config["replace_address"]:
                    if k in has_replace:
                        continue
                    if len(self.replace_address) == 0:
                        self.replace_address = f"--named-addresses {k}={self.network_config['replace_address'][k]}"
                    else:
                        self.replace_address += f',{k}={self.network_config["replace_address"][k]}'
                    has_replace[k] = True
            for k in self.move_toml["addresses"]:
                if k in has_replace:
                    continue
                if self.move_toml["addresses"][k] == "_":
                    if len(self.replace_address) == 0:
                        self.replace_address = f"--named-addresses {k}={self.account.account_address}"
                    else:
                        self.replace_address += f',{k}={self.account.account_address}'

        if is_compile:
            self.compile()

        # # # # # Bytecode
        self.build_path = self.package_path.joinpath(
            f"build/{self.package_name}")
        self.move_module_files = []
        bytecode_modules = self.build_path.joinpath("bytecode_modules")
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
        self.get_abis()
        reload_cache(self.cache_file)

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

    def publish_package(self, gas_budget=100000):
        # view = f"Publish {self.package_name}"
        # print("\n" + "-" * 50 + view + "-" * 50)
        # compile_cmd = f"sui client publish --gas-budget {gas_budget}"
        # os.system(compile_cmd)
        # print("-" * (100 + len(view)))
        # print("\n")

        view = f"Publish {self.package_name}"
        print("\n" + "-" * 50 + view + "-" * 50)
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_publish",
                "params": [
                    self.account.account_address,
                    self.base64(self.move_modules),
                    None,
                    gas_budget
                ]
            },
        )
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()
        result = self.execute_transaction(tx_bytes=result["result"]["txBytes"])
        # # # # Update package id
        for d in result.get("created", []):
            if "data" in d and "dataType" in d["data"]:
                if d["data"]["dataType"] == "package":
                    self.package_id = d["reference"]["objectId"]
                    self.get_abis()

        pprint(result)
        print("-" * (100 + len(view)))
        print("\n")
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return result

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
        response = self.client.post(
            f"{self.base_url}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_executeTransaction",
                "params": [
                    tx_bytes,
                    sig_scheme,
                    self.account.sign(tx_bytes).base64(),
                    self.account.public_key().base64(),
                    request_type
                ]
            },
        )
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        try:
            assert result["EffectsCert"]["effects"]["effects"]["status"]["status"] == "success", result
            result = result["EffectsCert"]["effects"]["effects"]
            if index_object:
                object_ids = []
                for k in ["created", "mutated"]:
                    for d in result.get(k, dict()):
                        if "reference" in d and "objectId" in d["reference"]:
                            object_ids.append(d["reference"]["objectId"])
                if len(object_ids):
                    object_details = self.get_objects(object_ids)
                    flag = False
                    for k in ["created", "mutated"]:
                        for i, d in enumerate(result.get(k, dict())):
                            if "reference" in d and "objectId" in d["reference"] \
                                    and d["reference"]["objectId"] in object_details:
                                object_detail = object_details[d["reference"]["objectId"]]
                                result[k][i] = object_detail
                                if "data" in object_detail and "type" in object_detail["data"]:
                                    object_type = ObjectType.from_type(object_detail["data"]["type"])
                                    insert_cache(object_type, d["reference"]["objectId"])
                                    flag = True
                    if flag:
                        persist_cache(self.cache_file)
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

        engine = ThreadExecutor()

        num = 4
        split_data = self.slice_data(object_ids, num)
        workers = [functools.partial(worker, m) for m in split_data]
        engine.run(workers)
        return result

    @retry(stop_max_attempt_number=3, wait_random_min=50, wait_random_max=100)
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        try:
            return result["details"]
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        for module_name in result:
            for struct_name in result[module_name].get("structs", dict()):
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
                            ob = type(f"{self.__class__.__name__}_{attr}", (object,), dict())()
                            setattr(final_object, attr, ob)
                            final_object = ob
                    setattr(final_object, attr_list[-1], CacheObject[object_type])
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
                            ob = type(f"{self.__class__.__name__}_{attr}", (object,), dict())()
                            setattr(final_object, attr, ob)
                            final_object = ob
                    func = functools.partial(self.submit_transaction, abi)
                    setattr(func, "simulate", functools.partial(self.simulate_transaction, abi))
                    setattr(final_object, attr_list[-1], func)

    def __getitem__(self, key):
        assert key in self.abis, f"key not found in abi"
        return functools.partial(self.submit_transaction, self.abis[key])

    def construct_transaction(
            self,
            abi: dict,
            param_args: list,
            ty_args: List[str] = None,
            gas_budget=100000,
    ):
        if ty_args is None:
            ty_args = []
        assert isinstance(list(ty_args), list) and len(
            abi["type_parameters"]) == len(ty_args), f"ty_args error: {abi['type_parameters']}"
        assert len(param_args) == len(abi["parameters"]), f'param_args error: {abi["parameters"]}'
        arguments = []
        if len(param_args):
            arguments = param_args

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
                    arguments,
                    None,
                    gas_budget
                ]
            },
        )
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return result

    def submit_transaction(
            self,
            abi: dict,
            *param_args,
            ty_args: List[str] = None,
            gas_budget=100000,
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
        :param param_args:
        :param abi:
        :param ty_args:
        :param gas_budget:
        :return:
        """
        result = self.construct_transaction(abi, param_args, ty_args, gas_budget)
        return self.execute_transaction(result["txBytes"])

    def simulate_transaction(
            self,
            abi: dict,
            *param_args,
            ty_args: List[str] = None,
            gas_budget=100000,
    ) -> Union[list | int]:
        """
        return_types: storage|gas
            storage: return storage changes
            gas: return gas
        """
        result = self.construct_transaction(abi, param_args, ty_args, gas_budget)
        return self.dry_run_transaction(result["txBytes"])

    def pay_all_sui(self, input_coins: list, recipient: str = None, gas_budget=100000):
        if recipient is None:
            recipient = self.account.account_address
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return self.execute_transaction(result["txBytes"])

    def pay_sui(self, input_coins: list, amounts: list, recipients: list = None, gas_budget=100000):
        if recipients is None:
            recipients = self.account.account_address
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return self.execute_transaction(result["txBytes"])

    def pay(self, input_coins: list, amounts: list, recipients: list = None, gas_budget=100000):
        if recipients is None:
            recipients = self.account.account_address
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return self.execute_transaction(result["txBytes"])

    def merge_coins(self, input_coins: list, gas_budget=100000):
        assert len(input_coins) >= 2
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return self.execute_transaction(result["txBytes"])

    def split_coin(self, input_coin: str, split_amounts: list, gas_budget=100000):
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()["result"]
        return self.execute_transaction(result["txBytes"])

    def get_table_item(self, table_handle: str, key_type: str, value_str: str, key: dict):
        pass

    def get_events(self, address: str, event_handle: str, field_name: str, limit: int = None):
        pass


if __name__ == "__main__":
    # todo!
    # 1. Support sui and coin
    # 2. Support vector
    # 3. Only notice current account coin
    c = SuiPackage("./Hello")
    c.publish_package()
    print(CacheObject)
    print(c.main1.Hello)
    pprint(c.main1.set_m(c.main1.Hello[-1], 10))
