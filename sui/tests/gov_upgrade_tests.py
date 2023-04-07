import sui_brownie
from sui_brownie import SuiObject

import dola_sui_sdk
from dola_sui_sdk import sui_project, DOLA_CONFIG, init as dola_sui_init, load as dola_sui_load

dola_sui_sdk.set_dola_project_path("../..")
sui_project.active_account("TestAccount")


def deploy_governance():
    serde_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("serde")
    )

    serde_package.program_publish_package()

    dola_types_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("dola_types")
    )

    dola_types_package.program_publish_package(
        replace_address=dict(serde=None))

    governance_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("governance")
    )

    governance_package.program_publish_package(
        replace_address=dict(serde=None, dola_types=None))


def deploy_upgradeable_contract():
    # deploy app manager
    app_manager_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("app_manager")
    )

    app_manager_package.program_publish_package(
        replace_address=dict(serde=None,
                             dola_types=None,
                             governance=None))


def deploy_test_proposal():
    test_proposal_package = sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("./proposals/test_proposal")
    )

    test_proposal_package.program_publish_package(
        replace_address=dict(serde=None,
                             dola_types=None,
                             governance=None,
                             app_manager=None)
    )


def deploy_test_package():
    deploy_governance()
    deploy_upgradeable_contract()
    deploy_test_proposal()


def test_proposal_package():
    return sui_brownie.SuiPackage(
        package_path=DOLA_CONFIG["DOLA_SUI_PATH"].joinpath("./proposals/test_proposal"),
        package_id=str(sui_project.TestProposal[-1])
    )


def create_proposal():
    """
    public entry fun create_proposal(governance_info: &mut GovernanceInfo, ctx: &mut TxContext)
    :return:
    """
    governance = dola_sui_load.governance_package()
    test_proposal = test_proposal_package()

    test_proposal.test.create_proposal(
        governance.genesis.GovernanceInfo[-1]
    )


def proposal():
    return f"{sui_project.Governance[-1]}::governance_v1::Proposal<{sui_project.TestProposal[-1]}" \
           f"::test::Certificate>"


def vote_proposal():
    """
    public entry fun vote_proposal(
        governance_info: &GovernanceInfo,
        proposal: &mut Proposal<Certificate>,
        proposal_info: &mut ProposalInfo,
        ctx: &mut TxContext
    )
    :return:
    """
    governance = dola_sui_load.governance_package()
    test_proposal = test_proposal_package()

    test_proposal.test.vote_proposal(
        governance.genesis.GovernanceInfo[-1],
        sui_project[SuiObject.from_type(proposal())][-1],
        test_proposal.test.ProposalInfo[-1]
    )


def join_app_manager():
    """
    public entry fun join_app_manager(
        governance_contract: &mut GovernanceContracts,
        total_app_info: &mut TotalAppInfo,
        dola_registry: &mut DolaContractRegistry,
        proposal_info: &mut ProposalInfo,
        upgrade_cap: UpgradeCap
    )
    :return:
    """
    governance = dola_sui_load.governance_package()
    app_manager = dola_sui_load.app_manager_package()
    dola_types = dola_sui_load.dola_types_package()
    test_proposal = test_proposal_package()
    upgrade_cap = dola_sui_load.get_upgrade_cap_by_package_id(test_proposal.package_id)

    test_proposal.test.join_app_manager(
        governance.genesis.GovernanceContracts[-1],
        app_manager.app_manager.TotalAppInfo[-1],
        dola_types.dola_contract.DolaContractRegistry[-1],
        test_proposal.test.ProposalInfo[-1],
        upgrade_cap
    )


def init_test_package():
    dola_sui_init.active_governance_v1()

    create_proposal()

    vote_proposal()

    join_app_manager()


def run():
    deploy_test_package()
    init_test_package()
