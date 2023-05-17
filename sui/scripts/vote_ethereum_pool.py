from pathlib import Path

import dola_ethereum_sdk
import dola_sui_sdk
from dola_ethereum_sdk import init as dola_ethereum_init
from dola_sui_sdk import init as dola_sui_init
from dola_sui_sdk import load as dola_sui_load
from dola_sui_sdk import sui_project
from sui_brownie import SuiObject, Argument, U16, NestedResult


def main(pool_id, pool_name):
    dola_chain_id = dola_ethereum_init.get_wormhole_chain_id()

    dola_protocol = dola_sui_load.dola_protocol_package()
    genesis_proposal = dola_sui_load.genesis_proposal_package()

    # Init poolmanager params
    # pool_address, dola_chain_id, pool_name, dola_pool_id, pool_weight
    wbtc_pool_params = [list(bytes.fromhex(dola_ethereum_init.wbtc().replace("0x", ""))), dola_chain_id, list(b"WBTC"),
                        0, 1]
    usdt_pool_params = [list(bytes.fromhex(dola_ethereum_init.usdt().replace("0x", ""))), dola_chain_id, list(b"USDT"),
                        1, 1]
    usdc_pool_params = [list(bytes.fromhex(dola_ethereum_init.usdc().replace("0x", ""))), dola_chain_id, list(b"USDC"),
                        2, 1]
    eth_pool_params = [list(bytes.fromhex(dola_ethereum_init.eth().replace("0x", ""))), dola_chain_id, list(pool_name),
                       pool_id, 1]

    dola_sui_init.create_proposal()

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        dola_sui_sdk.sui_project[SuiObject.from_type(dola_sui_init.proposal())][-1],  # 1
        dola_protocol.pool_manager.PoolManagerInfo[-1],  # 2
    ]

    pool_params = wbtc_pool_params + usdt_pool_params + usdc_pool_params + eth_pool_params

    sui_project.batch_transaction(
        actual_params=basic_params + pool_params,
        transactions=[
            [genesis_proposal.genesis_proposal.vote_proposal_final,
             [Argument("Input", U16(0)), Argument("Input", U16(1))],
             []
             ],  # 0. vote_proposal_final
            [
                genesis_proposal.genesis_proposal.register_new_pool,
                [Argument("NestedResult", NestedResult(U16(0), U16(0))),
                 Argument("NestedResult", NestedResult(U16(0), U16(1))),
                 Argument("Input", U16(2)),
                 Argument("Input", U16(3)),
                 Argument("Input", U16(4)),
                 Argument("Input", U16(5)),
                 Argument("Input", U16(6)),
                 Argument("Input", U16(7))],
                []
            ],  # 1. register_new_pool btc
            [
                genesis_proposal.genesis_proposal.register_new_pool,
                [Argument("NestedResult", NestedResult(U16(1), U16(0))),
                 Argument("NestedResult", NestedResult(U16(1), U16(1))),
                 Argument("Input", U16(2)),
                 Argument("Input", U16(8)),
                 Argument("Input", U16(9)),
                 Argument("Input", U16(10)),
                 Argument("Input", U16(11)),
                 Argument("Input", U16(12))],
                []
            ],  # 2. register_new_pool usdt
            [
                genesis_proposal.genesis_proposal.register_new_pool,
                [Argument("NestedResult", NestedResult(U16(2), U16(0))),
                 Argument("NestedResult", NestedResult(U16(2), U16(1))),
                 Argument("Input", U16(2)),
                 Argument("Input", U16(13)),
                 Argument("Input", U16(14)),
                 Argument("Input", U16(15)),
                 Argument("Input", U16(16)),
                 Argument("Input", U16(17))],
                []
            ],  # 3. register_new_pool usdc
            [
                genesis_proposal.genesis_proposal.register_new_pool,
                [Argument("NestedResult", NestedResult(U16(3), U16(0))),
                 Argument("NestedResult", NestedResult(U16(3), U16(1))),
                 Argument("Input", U16(2)),
                 Argument("Input", U16(18)),
                 Argument("Input", U16(19)),
                 Argument("Input", U16(20)),
                 Argument("Input", U16(21)),
                 Argument("Input", U16(22))],
                []
            ],  # 4. register_new_pool sui
            [genesis_proposal.genesis_proposal.destory,
             [Argument("NestedResult", NestedResult(U16(4), U16(0))),
              Argument("NestedResult", NestedResult(U16(4), U16(1)))],
             []
             ]
        ]
    )


if __name__ == "__main__":
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    dola_sui_sdk.sui_project.active_account("TestAccount")
    dola_ethereum_sdk.set_ethereum_network("polygon-test")
    main(4, b"MATIC")
