import sui_brownie
from dola_sui_sdk import DOLA_CONFIG, sui_project, load
from sui_brownie import SuiObject

net = "sui-testnet"

sui_project.active_account("Relayer1")


def deploy():
    upgrade_proposal_template_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("proposals/upgrade_proposal_template")
    )

    upgrade_proposal_template_package.program_publish_package(
        replace_address=dict(governance=None))


def upgrade_create_proposal():
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    upgrade_proposal_template = load.upgrade_proposal_template_package()
    governance = load.governance_package()
    upgrade_proposal_template.upgrade_proposal.create_proposal(
        governance.governance_v1.GovernanceInfo[-1])


def dola_upgrade():
    upgrade_proposal_template = load.upgrade_proposal_template_package()
    governance = load.governance_package()
    app_manager = load.app_manager_package()

    cur_proposal = f"{sui_project.Governance[-1]}::governance_v1::Proposal<{upgrade_proposal_template.package_id}" \
                   f"::upgrade_proposal::Certificate>"

    app_manager.program_dola_upgrade_package(
        upgrade_proposal_template.package_id,
        governance.governance_v1.GovernanceInfo[-1],
        governance.genesis.GovernanceContracts[-1],
        sui_project[SuiObject.from_type(cur_proposal)][-1],
        replace_address=dict(governance=None)
    )


def dola_upgrade_test():
    upgrade_create_proposal()
    dola_upgrade()


if __name__ == "__main__":
    deploy()
    dola_upgrade_test()
