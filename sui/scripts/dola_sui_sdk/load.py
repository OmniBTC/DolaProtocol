from pathlib import Path
from typing import Union

import sui_brownie
from sui_brownie import CacheObject
from dola_sui_sdk import DOLA_CONFIG


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


def omnipool_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.OmniPool[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnipool"))


def app_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.AppManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/app_manager"))


def governance_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Governance[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/governance"))


def oracle_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Oracle[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/oracle"))


def pool_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.PoolManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/pool_manager"))


def user_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.UserManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/user_manager"))


def wormhole_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Wormhole[-1]
    return sui_package(package_id,
                       Path.home().joinpath(Path(
                           ".move/https___github_com_OmniBTC_wormhole_git_e6e160614e1b2aeaaad3fd1c587571a3ee8a082d/sui/wormhole")))


def wormhole_bridge_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.WormholeBridge[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("wormhole_bridge"))


def lending_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.Lending[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/lending"))


def lending_portal_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.LendingPortal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("lending_portal"))


def external_interfaces_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.ExternalInterfaces[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces"))


def example_proposal_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.ExampleProposal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnicore/example_proposal"))


def test_coins_package(package_id: str = None):
    if package_id is None:
        package_id: str = CacheObject.TestCoins[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins"))
