from pathlib import Path

import sui_brownie
import yaml
from dola_sui_sdk import DOLA_CONFIG, sui_project

sui_project.active_account("TestAccount")


def export_to_config():
    path = Path(__file__).parent.parent.parent.joinpath("brownie-config.yaml")
    with open(path, "r") as f:
        config = yaml.safe_load(f)

    current_network = sui_project.network
    if "packages" not in config["networks"][current_network]:
        config["networks"][current_network]["packages"] = {}

    config["networks"][current_network]["packages"]["DolaProtocol"] = sui_project.DolaProtocol[-1]
    config["networks"][current_network]["packages"]["ExternalInterfaces"] = sui_project.ExternalInterfaces[-1]
    config["networks"][current_network]["packages"]["GenesisProposal"] = sui_project.GenesisProposal[-1]
    config["networks"][current_network]["packages"]["TestCoins"] = sui_project.TestCoins[-1]

    if "Wormhole" not in config["networks"][current_network]["packages"]:
        config["networks"][current_network]["packages"]["Wormhole"] = sui_project.Wormhole[-1]

    with open(path, "w") as f:
        yaml.safe_dump(config, f)


def deploy():
    wormhole_package = sui_brownie.SuiPackage(
        package_id=sui_project.network_config['packages']['Wormhole'],
        package_path=Path.home().joinpath(Path(
            ".move/https___github_com_wormhole-foundation_wormhole_git_d050ad1d67a5b7da9fb65030aad12ef5d774ccad/sui/wormhole")),
    )

    dola_protocol_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_protocol")
    )

    dola_protocol_package.program_publish_package(replace_address=dict(
        wormhole=wormhole_package.package_id,
        pyth=sui_project.network_config['packages']['Pyth']
    ), gas_budget=1000000000)

    external_interfaces_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces")
    )

    external_interfaces_package.program_publish_package(replace_address=dict(
        dola_protocol=dola_protocol_package.package_id,
        wormhole=wormhole_package.package_id
    ))

    genesis_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            "proposals/genesis_proposal")
    )

    genesis_proposal_package.program_publish_package(replace_address=dict(
        dola_protocol=dola_protocol_package.package_id,
        wormhole=wormhole_package.package_id
    ))

    test_coins_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins")
    )

    test_coins_package.program_publish_package()


def main():
    deploy()
    export_to_config()


if __name__ == "__main__":
    main()
