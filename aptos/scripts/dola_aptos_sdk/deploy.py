# @Time    : 2022/12/15 18:39
# @Author  : WeiDai
# @FileName: deploy.py

import aptos_brownie
from dola_aptos_sdk import DOLA_CONFIG

net = "aptos-testnet"

serde_package = aptos_brownie.AptosPackage(
    project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
    network=net,
    is_compile=True,
    package_path=DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("serde")
)

serde_package.publish_package()

dola_types_package = aptos_brownie.AptosPackage(
    project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
    network=net,
    is_compile=True,
    package_path=DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("dola_types")
)

dola_types_package.publish_package()

omnipool_package = aptos_brownie.AptosPackage(
    project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
    network=net,
    is_compile=True,
    package_path=DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("omnipool")
)

omnipool_package.publish_package()

wormhole_bridge_package = aptos_brownie.AptosPackage(
    project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
    network=net,
    is_compile=True,
    package_path=DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("wormhole_bridge")
)

wormhole_bridge_package.publish_package()

lending_portal_package = aptos_brownie.AptosPackage(
    project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
    network=net,
    is_compile=True,
    package_path=DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("lending_portal")
)

lending_portal_package.publish_package()

if net != "aptos-mainnet":
    test_coins_package = aptos_brownie.AptosPackage(
        project_path=DOLA_CONFIG["DOLA_APTOS_PATH"],
        network=net,
        is_compile=True,
        package_path=DOLA_CONFIG["DOLA_APTOS_PATH"].joinpath("test_coins")
    )

    test_coins_package.publish_package()
