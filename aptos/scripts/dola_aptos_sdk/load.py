import functools
from pathlib import Path
from typing import Union

import aptos_brownie
from dola_aptos_sdk import DOLA_CONFIG

net = "aptos-testnet"


@functools.lru_cache()
def aptos_package(package_path: Union[Path, str] = None):
    return aptos_brownie.AptosPackage(
        project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
        network=net,
        is_compile=True,
        package_path=package_path
    )


def serde_package():
    return aptos_package(DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("serde"))


def omnipool_package():
    return aptos_package(DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("omnipool"))


def wormhole_bridge_package():
    return aptos_package(DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("wormhole_bridge"))


def lending_portal_package():
    return aptos_package(DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("lending_portal"))


def test_coins_package():
    return aptos_package(DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("test_coins"))
