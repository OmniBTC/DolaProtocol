import functools
from pathlib import Path
from typing import Union

import sui_brownie
from dola_sui_sdk import DOLA_CONFIG
from sui_brownie import CacheObject


@functools.lru_cache()
def sui_package(package_id: str = None, package_path: Union[Path, str] = None):
    return sui_brownie.SuiPackage(
        brownie_config=DOLA_CONFIG["DOLA_SUI_PATH"],
        network="sui-devnet",
        is_compile=False,
        package_id=package_id,
        package_path=package_path
    )


def serde_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Serde[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("serde"))


def dola_types_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.DolaTypes[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_types"))


def omnipool_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.OmniPool[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnipool"))


def app_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.AppManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("app_manager"))


def governance_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Governance[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("governance"))


def oracle_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Oracle[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("oracle"))


def pool_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.PoolManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("pool_manager"))


def user_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.UserManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("user_manager"))


def wormhole_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Wormhole[-1]
    return sui_package(package_id,
                       Path.home().joinpath(Path(
                           ".move/https___github_com_OmniBTC_wormhole_git_9ad5da39a8cae4249e7dfcf3faa4ecac6239fd0a/sui/wormhole")))


def wormhole_adapter_core_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.WormholeAdapterCore[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("wormhole_adapter_core"))


def lending_core_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.LendingCore[-1]

    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("lending_core"))


def system_core_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.SystemCore[-1]

    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("system_core"))


def dola_portal_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.DolaPortal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_portal"))


def external_interfaces_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.ExternalInterfaces[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces"))


def genesis_proposal_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.GenesisProposal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/genesis_proposal"))


def test_coins_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.TestCoins[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins"))
