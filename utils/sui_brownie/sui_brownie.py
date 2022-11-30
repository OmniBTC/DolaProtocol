from __future__ import annotations

import base64
import copy
import functools
import json
import os
import traceback
from collections import OrderedDict
from pathlib import Path
from typing import Union, List, Dict
from pprint import pprint
from retrying import retry

import httpx
from dotenv import load_dotenv

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

CACHE_DIR = Path(os.environ.get('HOME')).joinpath(".cache")
if not CACHE_DIR.exists():
    CACHE_DIR.mkdir()

CACHE_FILE = CACHE_DIR.joinpath("objects.json")

CacheObject: Dict[Union[ObjectType, str], dict] = OrderedDict()


def persist_cache(cache_file=CACHE_FILE):
    data = {}
    for k in CacheObject:
        for m in CacheObject[k]:
            if len(CacheObject[k][m]):
                if k not in data:
                    data[str(k)] = {}
                data[str(k)][m] = CacheObject[k][m]
    if len(data) == 0:
        return
    pt = ThreadExecutor(executor=1, mode="all")

    def worker():
        with open(str(cache_file), "w") as f:
            json.dump(data, f, indent=4, sort_keys=True)

    pt.run([worker])


def reload_cache(cache_file: Path=CACHE_FILE):
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

    @retry(stop_max_attempt_number=3, wait_random_min=500, wait_random_max=1000)
    def get(self, *args, **kwargs):
        return super().get(*args, **kwargs)

    @retry(stop_max_attempt_number=3, wait_random_min=500, wait_random_max=1000)
    def post(self, *args, **kwargs):
        return super().post(*args, **kwargs)


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
        self.client = HttpClient(timeout=10)

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
                move_toml["addresses"][k] = replace_address[k]
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

    def publish_package(
            self,
            gas_budget=100000,
            replace_address: dict = None
    ):
        replace_tomls = self.replace_addresses(replace_address=replace_address, output=dict())
        view = f"Publish {self.package_name}"
        print("\n" + "-" * 50 + view + "-" * 50)
        with self.cli_config as cof:
            compile_cmd = f"sui client --client.config {cof.file.absolute()} publish " \
                          f"--path {self.package_path.absolute()} " \
                          f"--gas-budget {gas_budget} --abi --json"
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
                        persist_cache(CACHE_FILE)
        print("-" * (100 + len(view)))
        print("\n")

        for k in replace_tomls:
            replace_tomls[k].restore()

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
        # if response.status_code >= 400:
        #     raise ApiError(response.text, response.status_code)
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
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
                            if "Shared" in object_detail["owner"]:
                                insert_cache(object_type, d["reference"]["objectId"])
                                insert_cache(object_type, d["reference"]["objectId"], self.account.account_address)
                            else:
                                insert_cache(object_type, d["reference"]["objectId"], d["owner"]["AddressOwner"])
                            flag = True
            if flag:
                persist_cache(CACHE_FILE)

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
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        result = self.format_result(result)
        try:
            assert result["EffectsCert"]["effects"]["effects"]["status"]["status"] == "success", result
            result = result["EffectsCert"]["effects"]["effects"]
            if index_object:
                self.add_details(result)
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
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
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
                    if self.account.account_address not in CacheObject[object_type]:
                        CacheObject[object_type][self.account.account_address] = []
                    setattr(final_object, attr_list[-1], CacheObject[object_type][self.account.account_address])
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

    @staticmethod
    def judge_ctx(param) -> bool:
        if not isinstance(param, dict):
            return False
        final_arg = param.get("MutableReference", dict()).get("Struct", dict())
        if final_arg.get("address", None) == "0x2" \
                and final_arg.get("module", None) == "tx_context" \
                and final_arg.get("name", None) == "TxContext":
            return True
        else:
            return False

    @classmethod
    def cascade_type_arguments(cls, data) -> str:
        if len(data) == 0:
            return ""
        output = "<"
        for k, v in enumerate(data):
            if k != 0:
                output += ","
            data = "::".join([v["Struct"]["address"], v["Struct"]["module"], v["Struct"]["name"]])
            if len(v["Struct"]["type_arguments"]):
                data += cls.cascade_type_arguments(v["Struct"]["type_arguments"])
            output += data
        output += ">"
        return output

    @classmethod
    def generate_object_type(cls, param: str) -> ObjectType:
        if not isinstance(param, dict):
            return None
        if "Reference" in param:
            final_arg = param["Reference"]
        elif "MutableReference" in param:
            final_arg = param["MutableReference"]
        else:
            return None

        if "Struct" in final_arg:
            output = cls.cascade_type_arguments(final_arg["Struct"]["type_arguments"])
            output = f'{final_arg["Struct"]["address"]}::' \
                     f'{final_arg["Struct"]["module"]}::' \
                     f'{final_arg["Struct"]["name"]}{output}'
            return ObjectType.from_type(output)
        else:
            return None

    @classmethod
    def judge_coin(cls, param: str) -> ObjectType:
        data = cls.generate_object_type(param)
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
                owner = owner_info["AddressOwner"]
            coin_info[k] = Coin(k, owner, int(result[k]["data"]["fields"]["balance"]))
        return coin_info

    def construct_transaction(
            self,
            abi: dict,
            param_args: list,
            ty_args: List[str] = None,
            gas_budget=100000,
    ):
        param_args = list(param_args)
        if ty_args is None:
            ty_args = []
        assert isinstance(list(ty_args), list) and len(
            abi["type_parameters"]) == len(ty_args), f"ty_args error: {abi['type_parameters']}"
        if len(abi["parameters"]) and self.judge_ctx(abi["parameters"][-1]):
            assert len(param_args) == len(abi["parameters"]) - 1, f'param_args error: {abi["parameters"]}'
        else:
            assert len(param_args) == len(abi["parameters"]), f'param_args error: {abi["parameters"]}'

        normal_coin: List[ObjectType]  = []

        for k in range(len(param_args)):
            is_coin = self.judge_coin(abi["parameters"][k])
            if is_coin is None:
                continue
            if not isinstance(param_args[k], int):
                continue
            assert len(CacheObject[is_coin][self.account.account_address]), f"Not found coin"

            normal_coin.append(is_coin)

            # merge
            coin_info = self.get_coin_info(CacheObject[is_coin][self.account.account_address])
            CacheObject[is_coin][self.account.account_address] = sorted(coin_info.keys(),
                                                                        key=lambda x: coin_info[x].balance)[::-1]
            if len(CacheObject[is_coin][self.account.account_address]) > 1:
                if str(is_coin) == "0x2::coin::Coin<0x2::sui::SUI>":
                    self.pay_all_sui(
                        CacheObject[is_coin][self.account.account_address],
                        self.account.account_address,
                        gas_budget
                    )
                else:
                    self.merge_coins(CacheObject[is_coin][self.account.account_address], gas_budget)

            # split
            coin_info = self.get_coin_info(CacheObject[is_coin][self.account.account_address])
            CacheObject[is_coin][self.account.account_address] = sorted(coin_info.keys(),
                                                                        key=lambda x: coin_info[x].balance)[::-1]
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
            coin_info = self.get_coin_info(CacheObject[is_coin][self.account.account_address])
            CacheObject[is_coin][self.account.account_address] = sorted(coin_info.keys(),
                                                                        key=lambda x: coin_info[x].balance)[::-1]
            for oid in coin_info:
                if coin_info[oid].balance == param_args[k]:
                    param_args[k] = oid
                    break
            assert not isinstance(param_args[k], int), "Fail split amount"

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
                    None,
                    gas_budget
                ]
            },
        )

        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
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
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
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
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
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
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
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
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
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
        result = response.json()
        if "error" in result:
            assert False, result["error"]
        result = result["result"]
        return self.execute_transaction(result["txBytes"])

    def get_table_item(self, table_handle: str, key_type: str, value_str: str, key: dict):
        pass

    def get_events(self, address: str, event_handle: str, field_name: str, limit: int = None):
        pass
