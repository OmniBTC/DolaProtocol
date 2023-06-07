import json

import sui_brownie
from sui_brownie import SuiObject, SuiPackage

from dola_sui_sdk import DOLA_CONFIG, sui_project, load


def generate_package_info(package, replace_address: dict = None, replace_publish_at: dict = None):
    package: SuiPackage = getattr(load, f"{package}_package")()
    result = package.generate_digest(replace_address=replace_address, replace_publish_at=replace_publish_at)
    digest = bytes(json.loads(result)['digest']).hex()
    print(f"Package id:{package.package_id}, digest:{digest}")


def generate_dola_protocol_package_info():
    generate_package_info("dola_protocol", replace_address=dict(
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def deploy_upgrade_proposal():
    upgrade_proposal_template_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/upgrade_proposal_template")
    )

    upgrade_proposal_template_package.program_publish_package(
        replace_address=dict(dola_protocol=sui_project.network_config['packages']['dola_protocol']),
        replace_publish_at=dict(dola_protocol=get_latest_dola_protocol())
    )


def deploy_migrate_proposal():
    upgrade_proposal_template_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/migrate_version_proposal")
    )

    upgrade_proposal_template_package.program_publish_package(
        replace_address=dict(dola_protocol=sui_project.network_config['packages']['dola_protocol']),
        replace_publish_at=dict(dola_protocol=get_latest_dola_protocol())
    )


def upgrade_create_proposal():
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    upgrade_proposal_template = load.upgrade_proposal_template_package()
    upgrade_proposal_template.upgrade_proposal.create_proposal(
        sui_project.network_config['objects']['GovernanceInfo']
    )


def migrate_create_proposal():
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    migrate_version_proposal = load.migrate_version_proposal_package()
    migrate_version_proposal.migrate_proposal.create_proposal(
        sui_project.network_config['objects']['GovernanceInfo']
    )


def upgrade_dola_protocol():
    upgrade_proposal_template = load.upgrade_proposal_template_package()
    dola_protocol = load.dola_protocol_package(get_latest_dola_protocol())
    cur_proposal = f"{sui_project.network_config['packages']['dola_protocol']}::governance_v1::Proposal<{upgrade_proposal_template.package_id}" \
                   f"::upgrade_proposal::Certificate>"

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

    cur_proposal = f"{sui_project.network_config['packages']['dola_protocol']}::governance_v1::Proposal<{migrate_version_proposal.package_id}" \
                   f"::migrate_proposal::Certificate>"

    migrate_version_proposal.migrate_proposal.migrate_version(
        sui_project.network_config['objects']['GovernanceInfo'],
        sui_project[SuiObject.from_type(cur_proposal)][-1],
        sui_project.network_config['objects']['GovernanceGenesis'],
    )


def check_version(package_id=None):
    dola_protocol = load.dola_protocol_package(package_id)
    result = dola_protocol.genesis.check_version.simulate(
        sui_project.network_config['objects']['GovernanceGenesis']
    )
    print(result['effects']['status']['status'])


def dola_upgrade_test():
    deploy_upgrade_proposal()
    upgrade_create_proposal()
    upgrade_dola_protocol()


def migrate_version_test():
    # deploy_migrade_proposal()
    # migrate_create_proposal()
    migrate_version()


def get_latest_dola_protocol():
    governance_genesis = sui_project.network_config['objects']['GovernanceGenesis']
    result = sui_project.client.sui_getObject(governance_genesis, {'showContent': True})
    return result['data']['content']['fields']['upgrade_cap']['fields']['package']


if __name__ == "__main__":
    # generate_dola_protocol_package_info()
    # dola_upgrade_test()
    # migrate_version_test()
    check_version(sui_project.network_config['packages']['dola_protocol'])
    check_version(get_latest_dola_protocol())
