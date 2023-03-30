import functools
from pathlib import Path
from typing import Union

import sui_brownie
from dola_sui_sdk import DOLA_CONFIG

net = "devnet"
sui_project = sui_brownie.SuiProject(project_path=DOLA_CONFIG["DOLA_SUI_PATH"], network=net)
sui_project.active_account("Relayer")


@functools.lru_cache()
def sui_package(package_id: str = None, package_path: Union[Path, str] = None):
    return sui_brownie.SuiPackage(
        package_id=package_id,
        package_path=package_path
    )


def serde_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.Serde[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("serde"))


def dola_types_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.DolaTypes[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_types"))


def omnipool_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.OmniPool[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnipool"))


def app_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.AppManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("app_manager"))


def governance_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.Governance[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("governance"))


def oracle_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.Oracle[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("oracle"))


def pool_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.PoolManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("pool_manager"))


def user_manager_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.UserManager[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("user_manager"))


def wormhole_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.Wormhole[-1]
    return sui_package(package_id,
                       Path.home().joinpath(Path(
                           ".move/https___github_com_OmniBTC_wormhole_git_6fd072e39c386ab00fae9f9321ef14ab2c144e14/sui/wormhole")))


def wormhole_adapter_core_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.WormholeAdapterCore[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("wormhole_adapter_core"))


def lending_core_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.LendingCore[-1]

    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("lending_core"))


def system_core_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.SystemCore[-1]

    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("system_core"))


def dola_portal_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.DolaPortal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_portal"))


def external_interfaces_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.ExternalInterfaces[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces"))


def genesis_proposal_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.GenesisProposal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/genesis_proposal"))


def test_coins_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.TestCoins[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins"))
