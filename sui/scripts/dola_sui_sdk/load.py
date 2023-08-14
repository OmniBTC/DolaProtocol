import functools
from pathlib import Path
from typing import Union

import sui_brownie

from dola_sui_sdk import DOLA_CONFIG, sui_project

sui_project.active_account("TestAccount")


@functools.lru_cache()
def get_upgrade_cap_info(upgrade_cap_ids: tuple):
    result = sui_project.client.sui_multiGetObjects(
        upgrade_cap_ids,
        {
            "showType": True,
            "showOwner": True,
            "showPreviousTransaction": False,
            "showDisplay": False,
            "showContent": True,
            "showBcs": False,
            "showStorageRebate": False
        }
    )
    return {v["data"]["content"]["fields"]["package"]: v["data"] for v in result if "error" not in v}


def get_upgrade_cap_ids():
    return list(tuple(list(sui_project["0x2::package::UpgradeCap"])))


def get_upgrade_cap_by_package_id(package_id: str):
    upgrade_cap_ids = tuple(list(sui_project["0x2::package::UpgradeCap"]))
    info = get_upgrade_cap_info(upgrade_cap_ids)
    if package_id in info:
        return info[package_id]["objectId"]


@functools.lru_cache()
def sui_package(package_id: str = None, package_path: Union[Path, str] = None):
    return sui_brownie.SuiPackage(
        package_id=package_id,
        package_path=package_path
    )


def dola_protocol_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.network_config['packages']['dola_protocol']['latest']
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_protocol"))


def wormhole_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.network_config['packages']['wormhole']
    return sui_package(package_id,
                       Path.home().joinpath(Path(
                           ".move/https___github_com_wormhole-foundation_wormhole_git_fcfe551da0f46b704b76b09ae11dca3dd9387837/sui/wormhole")))


def pyth_package():
    return sui_brownie.SuiPackage(
        package_id=sui_project.network_config['packages']['pyth'],
        package_path=Path.home().joinpath(Path(
            ".move/https___github_com_pyth-network_pyth-crosschain_git_7dab308f961746890faf1ac0b52e283b31112bf6/target_chains/sui/contracts")),
    )


def external_interfaces_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.network_config['packages']['external_interfaces']
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces"))


def genesis_proposal_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.network_config['packages']['genesis_proposal']
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/genesis_proposal"))


def reserve_proposal_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.network_config['packages']['reserve_proposal']
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/reserve_params_proposal"))


def upgrade_proposal_package(package_id, file_dir):
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(f"proposals/upgrade_proposal/{file_dir}"))


def migrate_version_proposal_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.MigrateVersionProposal[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/migrate_version_proposal/migrate_version_1_0_0"))


def test_coins_package(package_id: str = None):
    if package_id is None:
        package_id: str = sui_project.TestCoins[-1]
    return sui_package(package_id, DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins"))
