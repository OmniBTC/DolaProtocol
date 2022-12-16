import functools
from pathlib import Path
from typing import Union

import aptos_brownie

net = "aptos-testnet"


@functools.lru_cache()
def aptos_package(package_path: Union[Path, str] = None):
    return aptos_brownie.AptosPackage(
        project_path=Path("../"),
        network=net,
        is_compile=True,
        package_path=package_path
    )


def serde_package():
    return aptos_package("../serde")


def omnipool_package():
    return aptos_package("../omnipool")


def wormhole_bridge_package():
    return aptos_package("../wormhole_bridge")


def lending_portal_package():
    return aptos_package("../lending_portal")


def test_coins_package():
    return aptos_package("../test_coins")
