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

    config["networks"][current_network]["packages"]["dola_protocol"] = sui_project.DolaProtocol[-1]
    config["networks"][current_network]["packages"]["genesis_proposal"] = sui_project.GenesisProposal[-1]
    config["networks"][current_network]["packages"]["external_interfaces"] = sui_project.ExternalInterfaces[-1]

    with open(path, "w") as f:
        yaml.safe_dump(config, f)


def export_package_to_config(package_name, package_id):
    path = Path(__file__).parent.parent.parent.joinpath("brownie-config.yaml")
    with open(path, "r") as f:
        config = yaml.safe_load(f)

    current_network = sui_project.network

    config["networks"][current_network]["packages"][package_name] = package_id

    with open(path, "w") as f:
        yaml.safe_dump(config, f)


def deploy_add_member(file_dir):
    add_member_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            f"proposals/manage_member_proposal/{file_dir}")
    )

    add_member_proposal_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))

    print("Package id:", add_member_proposal_package.package_id)


def prepare_proposal(package_id):
    proposal = sui_brownie.SuiPackage(
        package_id=package_id,
        package_name="proposal"
    )
    result = proposal.proposal.create_proposal(
        sui_project.network_config['objects']['GovernanceInfo']
    )
    proposal_id = result["events"][0]["parsedJson"]["proposal_id"]
    print("proposal_id:", proposal_id)
    proposal.proposal.add_description_for_proposal(
        proposal_id
    )


def deploy_register_pool(file_dir):
    register_pool_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            f"proposals/pool_manager_proposal/{file_dir}")
    )

    register_pool_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))

    print("Package id:", register_pool_package.package_id)
    prepare_proposal(register_pool_package.package_id)


def deploy():
    dola_protocol_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_protocol")
    )

    dola_protocol_package.program_publish_package(replace_address=dict(
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ), gas_budget=1000000000)

    genesis_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            "proposals/genesis_proposal")
    )

    genesis_proposal_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))

    if sui_project.network != "sui-mainnet":
        test_coins_package = sui_brownie.SuiPackage(
            package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("test_coins")
        )

        test_coins_package.program_publish_package()

    external_interfaces_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces")
    )

    external_interfaces_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def redeploy_genesis_proposal():
    genesis_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            "proposals/genesis_proposal")
    )

    genesis_proposal_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def redeploy_external_interfaces():
    external_interfaces_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("external_interfaces")
    )

    external_interfaces_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def redeploy_reserve_proposal():
    reserve_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/reserve_params_proposal")
    )

    reserve_proposal_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def main():
    deploy()
    export_to_config()


if __name__ == "__main__":
    redeploy_external_interfaces()
    # redeploy_genesis_proposal()
    # redeploy_reserve_proposal()
    deploy_register_pool("register_new_pool_20230812")
