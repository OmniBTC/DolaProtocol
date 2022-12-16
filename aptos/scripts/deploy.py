# @Time    : 2022/12/15 18:39
# @Author  : WeiDai
# @FileName: deploy.py
from pathlib import Path

import aptos_brownie

net = "aptos-testnet"

serde_package = aptos_brownie.AptosPackage(
    project_path=Path("../"),
    network=net,
    is_compile=True,
    package_path="../serde"
)

serde_package.publish_package()

dola_types_package = aptos_brownie.AptosPackage(
    project_path=Path("../"),
    network=net,
    is_compile=True,
    package_path="../dola_types"
)

dola_types_package.publish_package()

omnipool_package = aptos_brownie.AptosPackage(
    project_path=Path("../"),
    network=net,
    is_compile=True,
    package_path="../omnipool"
)

omnipool_package.publish_package()

wormhole_bridge_package = aptos_brownie.AptosPackage(
    project_path=Path("../"),
    network=net,
    is_compile=True,
    package_path="../wormhole_bridge"
)

wormhole_bridge_package.publish_package()

lending_portal_package = aptos_brownie.AptosPackage(
    project_path=Path("../"),
    network=net,
    is_compile=True,
    package_path="../lending_portal"
)

lending_portal_package.publish_package()

if net != "aptos-mainnet":
    test_coins_package = aptos_brownie.AptosPackage(
        project_path=Path("../"),
        network=net,
        is_compile=True,
        package_path="../test_coins"
    )

    test_coins_package.publish_package()
