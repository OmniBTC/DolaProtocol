import json

import sui_brownie
from sui_brownie import SuiObject, SuiPackage

from dola_sui_sdk import DOLA_CONFIG, sui_project, load


def generate_package_info(package, replace_address: dict = None, replace_publish_at: dict = None):
    # note
    package: SuiPackage = getattr(load, f"{package}_package")()
    result = package.generate_digest(replace_address=replace_address, replace_publish_at=replace_publish_at)
    digest = bytes(json.loads(result)['digest']).hex()
    print(f"Package id:{package.package_id}, digest:{digest}")


def generate_dola_protocol_package_info():
    generate_package_info("dola_protocol", replace_address=dict(
        dola_protocol="0x0",
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def deploy_upgrade_proposal(file_dir):
    upgrade_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(f"proposals/upgrade_proposal/{file_dir}")
    )

    upgrade_proposal_package.program_publish_package(
        replace_address=dict(dola_protocol=sui_project.network_config['packages']['dola_protocol']['origin']),
        replace_publish_at=dict(dola_protocol=get_latest_dola_protocol())
    )
    print("package id:", upgrade_proposal_package.package_id)

    upgrade_create_proposal(package_id=upgrade_proposal_package.package_id,
                            file_dir="upgrade_proposal_V_1_0_6")


def deploy_migrate_proposal(version):
    upgrade_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath(
            f"proposals/migrate_version_proposal/migrate_{version.lower()}")
    )

    upgrade_proposal_package.program_publish_package(
        replace_address=dict(
            dola_protocol=sui_project.network_config['packages']['dola_protocol']["origin"],
            wormhole=sui_project.network_config['packages']['wormhole'],
            pyth=sui_project.network_config['packages']['pyth']
        ),
        replace_publish_at=dict(
            dola_protocol=get_latest_dola_protocol(),
            wormhole=sui_project.network_config['packages']['wormhole'],
            pyth=sui_project.network_config['packages']['pyth'],
        )
    )


def upgrade_create_proposal(package_id, file_dir):
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    upgrade_proposal_template = load.upgrade_proposal_package(package_id, file_dir=file_dir)
    result = upgrade_proposal_template.proposal.create_proposal(
        sui_project.network_config['objects']['GovernanceInfo']
    )
    proposal_id = result["events"][0]["parsedJson"]["proposal_id"]
    print("proposal_id:", proposal_id)
    upgrade_proposal_template.proposal.add_description_for_proposal(
        proposal_id
    )


def migrate_create_proposal():
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    migrate_version_proposal = load.migrate_version_proposal_package()
    result = migrate_version_proposal.proposal.create_proposal(
        sui_project.network_config['objects']['GovernanceInfo']
    )
    proposal_id = result["events"][0]["parsedJson"]["proposal_id"]
    print("proposal_id:", proposal_id)
    migrate_version_proposal.proposal.add_description_for_proposal(
        proposal_id
    )


def upgrade_dola_protocol(package_id, file_dir):
    upgrade_proposal_template = load.upgrade_proposal_package(package_id, file_dir)
    dola_protocol = load.dola_protocol_package(get_latest_dola_protocol())
    cur_proposal = f"{sui_project.network_config['packages']['dola_protocol']['origin']}::governance_v1::Proposal<{upgrade_proposal_template.package_id}" \
                   f"::proposal::Certificate>"

    dola_protocol.program_dola_upgrade_package(
        upgrade_proposal_template.package_id,
        sui_project.network_config['objects']['GovernanceInfo'],
        sui_project.network_config['objects']['GovernanceGenesis'],
        sui_project[SuiObject.from_type(cur_proposal)][-1],
        replace_address=dict(
            wormhole=sui_project.network_config['packages']['wormhole'],
            pyth=sui_project.network_config['packages']['pyth']
        ), replace_publish_at=dict(
            wormhole=sui_project.network_config['packages']['wormhole'],
            pyth=sui_project.network_config['packages']['pyth'],
        ),
        gas_budget=1000000000
    )


def migrate_version():
    migrate_version_proposal = load.migrate_version_proposal_package()

    cur_proposal = f"{sui_project.network_config['packages']['dola_protocol']['origin']}::governance_v1::Proposal<{migrate_version_proposal.package_id}" \
                   f"::migrate_proposal::Certificate>"

    migrate_version_proposal.migrate_proposal.migrate_version(
        sui_project.network_config['objects']['GovernanceInfo'],
        sui_project[SuiObject.from_type(cur_proposal)][-1],
        sui_project.network_config['objects']['GovernanceGenesis'],
    )


def check_version(package_id=None):
    dola_protocol = load.dola_protocol_package(package_id)
    result = dola_protocol.genesis.check_latest_version.simulate(
        sui_project.network_config['objects']['GovernanceGenesis']
    )
    print(result['effects']['status']['status'])


def migrate_version():
    deploy_migrate_proposal(version="version_1_0_4")
    # migrate_create_proposal()
    # migrate_version()


def get_latest_dola_protocol():
    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    result = sui_project.client.sui_getObject(governance_genesis, {'showContent': True})
    return result['data']['content']['fields']['upgrade_cap']['fields']['package']


if __name__ == "__main__":
    """
    Upgrade step:
        1. generate_dola_protocol_package_info to generate digest:
            - note: dola_protocol is 0x0, publish at is latest
        2. dola_upgrade to upgrade:
            - deploy upgrade:  dola_protocol is origin, publish at is latest
            - call upgrade:  dola_protocol is 0x0, publish at is latest
        3. after the front-end upgrade, migrate_version
    """
    # generate_dola_protocol_package_info()
    # deploy_upgrade_proposal("upgrade_proposal_V_1_0_6")
    upgrade_dola_protocol(
        package_id="0x5e3e4eb7dc8e8230bd4c18777d5db7ff3ae821db32e921dfb2c150087c7bf90b",
        file_dir="upgrade_proposal_V_1_0_6"
    )

    # migrate_version()
    # check_version(sui_project.network_config['packages']['dola_protocol']['v_1_0_4'])
    # check_version(sui_project.network_config['packages']['dola_protocol']['v_1_0_5'])
    # check_version(get_latest_dola_protocol())
