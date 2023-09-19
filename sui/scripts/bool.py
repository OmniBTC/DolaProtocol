from pathlib import Path
from sui_brownie import SuiObject, SuiPackage, Argument, U16
import dola_sui_sdk
import dola_ethereum_sdk
from dola_sui_sdk import load
from dola_sui_sdk.deploy import main as deploy_main
from dola_sui_sdk.init import batch_init
from dola_sui_sdk import sui_project
from dola_ethereum_sdk import set_ethereum_network
from dola_ethereum_sdk.deploy import deploy_bool_adapter
from dola_ethereum_sdk.init import bool_adapter_init
from dola_ethereum_sdk.load import bool_anchor_package

dola_sui_sdk.set_dola_project_path(
    Path(__file__).parent.parent.parent,
    network="sui-testnet"
)
sui_project.active_account("TestAccount")

dola_ethereum_sdk.set_dola_project_path(
    Path(__file__).parent.parent.parent,
)
set_ethereum_network("bevm-test")


def zpad32_left(anchor: str):
    return "0x" + bytes.fromhex(anchor.replace("0x", "")).rjust(32, b"\x00").hex()


def deploy_sui():
    deploy_main()


def init_sui():
    batch_init()


def deploy_bevm():
    deploy_bool_adapter()


def init_bevm():
    bool_adapter_init()


def get_bool_messenger():
    anchor = bool_anchor_package("0x45395fc32da85a18285639f881cc1b7785c91091")
    print(anchor.messenger())


def deploy_bool_proposal():
    register_path_package = SuiPackage(
        package_path=Path(sui_project.project_path).joinpath("proposals/bool_proposal")
    )
    register_path_package.program_publish_package(replace_address=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth']
    ), replace_publish_at=dict(
        dola_protocol=sui_project.network_config['packages']['dola_protocol']['latest'],
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def proposal_type(register_path_package):
    dola_protocol = sui_project.network_config['packages']['dola_protocol']['origin']
    return f"{dola_protocol}::governance_v1::Proposal<{register_path_package}" \
           f"::proposal::Certificate>"


def bool_register_path(
        dst_dola_chainid=1502,
        dst_chain_id=1502,
        dst_anchor="0x45395fc32da85a18285639f881cc1b7785c91091"
):
    # public fun register_path(
    #     _: &GovernanceCap,
    #     core_state: &mut CoreState,
    #     dola_chain_id: u16,
    #     dst_chain_id: u32,
    #     dst_anchor: address,
    #     bool_global_state: &mut GlobalState,
    # )

    dst_anchor = zpad32_left(dst_anchor)
    print(f"dst_anchor={dst_anchor}")

    bool_proposal_package = SuiPackage(
        package_id="0xa75f70081742f937eb68eaebef9cc06aff00436ecf84d1b8542dd1f232d4286f",
        package_path=Path(sui_project.project_path).joinpath("proposals/bool_proposal")
    )
    dola_protocol = load.dola_protocol_package()

    core_state = sui_project.network_config['bool_network']['core_state']
    bool_global = sui_project.network_config['bool_network']['global_state']

    bool_proposal_package.proposal.create_proposal(
        dola_protocol.governance_v1.GovernanceInfo[-1]
    )

    register_path_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal_type(bool_proposal_package.package_id))][-1],  # 1
        core_state,  # 2
        dst_dola_chainid,  # 3
        dst_chain_id,  # 4
        dst_anchor,  # 5
        bool_global  # 6
    ]

    vote_proposal_final_tx_block = [
        [
            bool_proposal_package.proposal.vote_proposal_final,
            [Argument("Input", U16(0)), Argument("Input", U16(1))],
            []
        ]
    ]

    register_path_tx_block = [
        [
            bool_proposal_package.proposal.bool_register_path,
            [
                Argument("Result", U16(0)),  # HotPotato
                Argument("Input", U16(2)),
                Argument("Input", U16(3)),
                Argument("Input", U16(4)),
                Argument("Input", U16(5)),
                Argument("Input", U16(6)),
            ],
            []
        ]
    ]

    finish_proposal_tx_block = [
        [
            bool_proposal_package.proposal.destory,
            [
                Argument("Result", U16(1)),  # HotPotato
            ],
            []
        ]
    ]

    sui_project.batch_transaction(
        actual_params=register_path_params,
        transactions=vote_proposal_final_tx_block + register_path_tx_block + finish_proposal_tx_block
    )


def bool_release_anchor_cap(receiver):
    # public fun release_anchor_cap(
    #     _: &GovernanceCap,
    #     core_state: &mut CoreState,
    #     receiver: address
    # )

    bool_proposal_package = SuiPackage(
        package_id="0xa75f70081742f937eb68eaebef9cc06aff00436ecf84d1b8542dd1f232d4286f",
        package_path=Path(sui_project.project_path).joinpath("proposals/bool_proposal")
    )
    dola_protocol = load.dola_protocol_package()

    core_state = sui_project.network_config['bool_network']['core_state']

    bool_proposal_package.proposal.create_proposal(
        dola_protocol.governance_v1.GovernanceInfo[-1]
    )

    release_anchor_cap_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal_type(bool_proposal_package.package_id))][-1],  # 1
        core_state,  # 2
        receiver,  # 3
    ]

    vote_proposal_final_tx_block = [
        [
            bool_proposal_package.proposal.vote_proposal_final,
            [Argument("Input", U16(0)), Argument("Input", U16(1))],
            []
        ]
    ]

    release_anchor_cap_tx_block = [
        [
            bool_proposal_package.proposal.bool_release_anchor_cap,
            [
                Argument("Result", U16(0)),  # HotPotato
                Argument("Input", U16(2)),
                Argument("Input", U16(3)),
            ],
            []
        ]
    ]

    finish_proposal_tx_block = [
        [
            bool_proposal_package.proposal.destory,
            [
                Argument("Result", U16(1)),  # HotPotato
            ],
            []
        ]
    ]

    sui_project.batch_transaction(
        actual_params=release_anchor_cap_params,
        transactions=vote_proposal_final_tx_block + release_anchor_cap_tx_block + finish_proposal_tx_block
    )


def bool_set_anchor_cap(bool_anchor_cap):
    # public fun set_anchor_cap(
    #     _: &GovernanceCap,
    #     core_state: &mut CoreState,
    #     bool_anchor_cap: AnchorCap
    # )

    bool_proposal_package = SuiPackage(
        package_id="0xa75f70081742f937eb68eaebef9cc06aff00436ecf84d1b8542dd1f232d4286f",
        package_path=Path(sui_project.project_path).joinpath("proposals/bool_proposal")
    )
    dola_protocol = load.dola_protocol_package()

    core_state = sui_project.network_config['bool_network']['core_state']

    bool_proposal_package.proposal.create_proposal(
        dola_protocol.governance_v1.GovernanceInfo[-1]
    )

    set_anchor_cap_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        sui_project[SuiObject.from_type(proposal_type(bool_proposal_package.package_id))][-1],  # 1
        core_state,  # 2
        bool_anchor_cap,  # 3
    ]

    vote_proposal_final_tx_block = [
        [
            bool_proposal_package.proposal.vote_proposal_final,
            [Argument("Input", U16(0)), Argument("Input", U16(1))],
            []
        ]
    ]

    set_anchor_cap_tx_block = [
        [
            bool_proposal_package.proposal.bool_set_anchor_cap,
            [
                Argument("Result", U16(0)),  # HotPotato
                Argument("Input", U16(2)),
                Argument("Input", U16(3)),
            ],
            []
        ]
    ]

    finish_proposal_tx_block = [
        [
            bool_proposal_package.proposal.destory,
            [
                Argument("Result", U16(1)),  # HotPotato
            ],
            []
        ]
    ]

    sui_project.batch_transaction(
        actual_params=set_anchor_cap_params,
        transactions=vote_proposal_final_tx_block + set_anchor_cap_tx_block + finish_proposal_tx_block
    )


if __name__ == '__main__':
    deploy_sui()
