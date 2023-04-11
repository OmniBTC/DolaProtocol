from pathlib import Path

import sui_brownie

from dola_sui_sdk import DOLA_CONFIG, sui_project

net = "sui-testnet"

sui_project.active_account("Relayer1")

serde_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("serde")
)

serde_package.program_publish_package()

dola_types_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_types")
)

dola_types_package.program_publish_package(
    replace_address=dict(serde=None))

ray_math_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("ray_math")
)

ray_math_package.program_publish_package()

governance_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("governance")
)

governance_package.program_publish_package()

user_manager_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("user_manager")
)

user_manager_package.program_publish_package(
    replace_address=dict(serde=None,
                         dola_types=None,
                         governance=None))

app_manager_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("app_manager")
)

app_manager_package.program_publish_package(
    replace_address=dict(governance=None))

oracle_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("oracle")
)

oracle_package.program_publish_package()

pool_manager_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("pool_manager")
)

pool_manager_package.program_publish_package(
    replace_address=dict(serde=None, governance=None,
                         dola_types=None, ray_math=None))

wormhole_package = sui_brownie.SuiPackage(
    package_path=Path.home().joinpath(Path(
        ".move/https___github_com_OmniBTC_wormhole_git_d0e0d1743df2430d874459bd870f590f660f0ae8/sui/wormhole")),
)

wormhole_package.program_publish_package()

omnipool_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("omnipool")
)

omnipool_package.program_publish_package(replace_address=dict(
    serde=None,
    dola_types=None,
    wormhole=None
)
)

wormhole_adapter_core_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("wormhole_adapter_core")
)

wormhole_adapter_core_package.program_publish_package(replace_address=dict(
    wormhole_adapter_core="0x0",
    serde=None,
    ray_math=None,
    dola_types=None,
    wormhole=None,
    governance=None,
    app_manager=None,
    pool_manager=None,
    user_manager=None
)
)

lending_core_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("lending_core")
)

lending_core_package.program_publish_package(replace_address=dict(
    lending_core="0x0",
    serde=None,
    dola_types=None,
    ray_math=None,
    oracle=None,
    app_manager=None,
    pool_manager=None,
    user_manager=None,
    wormhole=None,
    wormhole_adapter_core=None,
    governance=None
)
)

system_core_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("system_core")
)

system_core_package.program_publish_package(replace_address=dict(
    serde=None,
    ray_math=None,
    pool_manager=None,
    dola_types=None,
    app_manager=None,
    user_manager=None,
    wormhole=None,
    wormhole_adapter_core=None,
    governance=None
)
)

dola_portal_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_portal")
)

dola_portal_package.program_publish_package(replace_address=dict(
    serde=None,
    ray_math=None,
    dola_types=None,
    pool_manager=None,
    user_manager=None,
    app_manager=None,
    lending_core=None,
    system_core=None,
    oracle=None,
    wormhole_adapter_core=None,
    wormhole=None,
    omnipool=None,
    governance=None
)
)

external_interfaces_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces")
)

external_interfaces_package.program_publish_package(replace_address=dict(
    pool_manager=None,
    user_manager=None,
    app_manager=None,
    governance=None,
    serde=None,
    wormhole_adapter_core=None,
    wormhole=None,
    omnipool=None,
    dola_types=None,
    lending_core=None,
    ray_math=None,
    oracle=None
))

genesis_proposal_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
        "proposals/genesis_proposal")
)

genesis_proposal_package.program_publish_package(replace_address=dict(
    pool_manager=None,
    user_manager=None,
    ray_math=None,
    serde=None,
    wormhole=None,
    wormhole_adapter_core=None,
    governance=None,
    lending_core=None,
    system_core=None,
    dola_portal=None,
    app_manager=None,
    dola_types=None,
    oracle=None,
    omnipool=None
)
)

test_coins_package = sui_brownie.SuiPackage(
    package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins")
)

test_coins_package.program_publish_package()

print("---------------------------Deployed Package ID-------------------------------------\n")
print(f"serde={sui_project.Serde[-1]}")
print(f"dola_types={sui_project.DolaTypes[-1]}")
print(f"ray_math={sui_project.RayMath[-1]}")
print(f"omnipool={sui_project.OmniPool[-1]}")
print(f"app_manager={sui_project.AppManager[-1]}")
print(f"governance={sui_project.Governance[-1]}")
print(f"oracle={sui_project.Oracle[-1]}")
print(f"pool_manager={sui_project.PoolManager[-1]}")
print(f"wormhole={sui_project.Wormhole[-1]}")
print(f"wormhole_adapter_core={sui_project.WormholeAdapterCore[-1]}")
print(f"lending_core={sui_project.LendingCore[-1]}")
print(f"system_core={sui_project.SystemCore[-1]}")
print(f"dola_portal={sui_project.DolaPortal[-1]}")
print(f"external_interfaces={sui_project.ExternalInterfaces[-1]}")
print(f"genesis_proposal={sui_project.GenesisProposal[-1]}")
print(f"test_coins={sui_project.TestCoins[-1]}")
