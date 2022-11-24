from __future__ import annotations

import base64
import functools
import os
from collections import OrderedDict
from pathlib import Path
from typing import Union, List
from pprint import pprint

import httpx
from dotenv import load_dotenv

from account import Account

import yaml
import toml

from Parallelism import ThreadExecutor


class ApiError(Exception):
    """Error thrown when the API returns >= 400"""

    def __init__(self, message, status_code):
        # Call the base class constructor with the parameters it needs
        super().__init__(message)
        self.status_code = status_code


class SuiPackage:
    def __init__(self,
                 project_path: Union[Path, str] = Path.cwd(),
                 network: str = "sui-devnet",
                 is_compile: bool = True,
                 package_id: str = None,
                 package_path: Union[Path, str] = None
                 ):
        """
        :param project_path: The folder where brownie-config.yaml is located.
        :param network:
        :param is_compile:
        :param package_path: The folder where Move.toml is located. Mostly the same as project_path.
        """
        self.package_id = package_id
        if isinstance(project_path, Path):
            self.project_path = project_path
        else:
            self.project_path = Path(project_path)
        self.network = network

        if package_path is None:
            self.package_path = self.project_path
        elif isinstance(package_path, str):
            self.package_path = Path(package_path)
        else:
            self.package_path = package_path

        # # # # # load config
        assert self.project_path.joinpath(
            "brownie-config.yaml").exists(), "brownie-config.yaml not found"
        self.config_path = self.project_path.joinpath("brownie-config.yaml")
        self.config = {}  # all network configs
        with self.config_path.open() as fp:
            self.config = yaml.safe_load(fp)
        try:
            load_dotenv(self.project_path.joinpath(self.config["dotenv"]))
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

        # # # # Metadata
        self.build_path = self.package_path.joinpath(
            f"build/{self.package_name}")
        # # # # # Bytecode
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
        self.cache_object = {}
        self.abis = {}

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
        for d in result.get("created", []):
            if "data" in d and "dataType" in d["data"]:
                if d["data"]["dataType"] == "package":
                    self.package_id = d["reference"]["objectId"]
                elif d["data"]["dataType"] == "moveObject":
                    if d["data"]["type"] not in self.cache_object:
                        self.cache_object[d["data"]["type"]] = OrderedDict()
                    self.cache_object[d["data"]["type"]][d["reference"]["objectId"]] = d

        pprint(result)
        print("-" * (100 + len(view)))
        print("\n")
        return result

    def execute_transaction(self,
                            tx_bytes,
                            sig_scheme="ED25519",
                            request_type="WaitForLocalExecution",
                            index_object: bool = True
                            ):
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
                    for d in result[k]:
                        if "reference" in d and "objectId" in d["reference"]:
                            object_ids.append(d["reference"]["objectId"])
                if len(object_ids):
                    object_details = self.get_objects(object_ids)
                    for k in ["created", "mutated"]:
                        for i, d in enumerate(result[k]):
                            if "reference" in d and "objectId" in d["reference"] \
                                    and d["reference"]["objectId"] in object_details:
                                result[k][i] = object_details[d["reference"]["objectId"]]
            return result
        except:
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
            if "exposed_functions" not in result[module_name]:
                continue
            for func_name in result[module_name]["exposed_functions"]:
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

    def submit_transaction(
            self,
            abi: dict,
            *args,
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
        :param abi:
        :param args:
        :param ty_args:
        :param gas_budget:
        :return:
        """
        if ty_args is None:
            ty_args = []
        print(abi)
        assert isinstance(list(ty_args), list) and len(
            abi["type_parameters"]) == len(ty_args), f"ty_args error: {abi['type_parameters']}"
        assert len(args) == len(abi["parameters"]), f'args error: {abi["parameters"]}'
        arguments = []
        if len(args):
            arguments = args

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
        result = response.json()
        print("move call", result)

    def simulate_transaction(
            self,
            abi: dict,
            *args,
            ty_args: List[str] = None,
            max_gas_amount=500000,
            gas_unit_price=100,
            return_types="storage",
            **kwargs,
    ) -> Union[list | int]:
        """
        return_types: storage|gas
            storage: return storage changes
            gas: return gas
        """
        pass

    def estimate_gas_price(self):
        try:
            result = self.client.get(url=f"{self.base_url}/estimate_gas_price").json()
            return int(result["gas_estimate"])
        except Exception as e:
            print(f"Estimate gas price fail:{e}, using default 100")
            return 100

    def get_table_item(self, table_handle: str, key_type: str, value_str: str, key: dict):
        pass

    def get_events(self, address: str, event_handle: str, field_name: str, limit: int = None):
        pass


if __name__ == "__main__":
    c = SuiPackage("./Hello")
    c.publish_package()
    c.get_abis()
    c.main1.set_m("0x160a17ab678ca502efd8baba75522553249d78c6", 10)
