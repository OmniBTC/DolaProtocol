from pathlib import Path
from typing import Union

import sui_brownie
from sui_brownie import CacheObject


def sui_package(package_id: str = None, package_path: Union[Path, str] = None):
    return sui_brownie.SuiPackage(
        brownie_config=Path("../"),
        network="sui-devnet",
        is_compile=False,
        package_id=package_id,
        package_path=package_path
    )


def serde_package(package_id: str = CacheObject.Serde[-1]):
    return sui_package(package_id, "../serde")


def omnipool_package(package_id: str = CacheObject.OmniPool[-1]):
    return sui_package(package_id, "../omnipool")


def app_manager_package(package_id: str = CacheObject.AppManager[-1]):
    return sui_package(package_id, "../omnicore/app_manager")


def governance_package(package_id: str = CacheObject.Governance[-1]):
    return sui_package(package_id, "../omnicore/governance")


def oracle_package(package_id: str = CacheObject.Oracle[-1]):
    return sui_package(package_id, "../omnicore/oracle")


def pool_manager_package(package_id: str = CacheObject.PoolManager[-1]):
    return sui_package(package_id, "../omnicore/pool_manager")


def user_manager_package(package_id: str = CacheObject.UserManager[-1]):
    return sui_package(package_id, "../omnicore/user_manager")


def wormhole_package(package_id: str = CacheObject.Wormhole[-1]):
    return sui_package(package_id,
                       Path.home().joinpath(Path(
                           ".move/https___github_com_OmniBTC_wormhole_git_e6e160614e1b2aeaaad3fd1c587571a3ee8a082d/sui/wormhole")))


def wormhole_bridge_package(package_id: str = CacheObject.WormholeBridge[-1]):
    return sui_package(package_id, "../wormhole_bridge")


def lending_package(package_id: str = CacheObject.Lending[-1]):
    return sui_package(package_id, "../omnicore/lending")


def lending_portal_package(package_id: str = CacheObject.LendingPortal[-1]):
    return sui_package(package_id, "../lending_portal")


def external_interfaces_package(package_id: str = CacheObject.ExternalInterfaces[-1]):
    return sui_package(package_id, "../external_interfaces")


def example_proposal_package(package_id: str = CacheObject.ExampleProposal[-1]):
    return sui_package(package_id, "../omnicore/example_proposal")


def test_coins_package(package_id: str = CacheObject.TestCoins[-1]):
    return sui_package(package_id, "../test_coins")
