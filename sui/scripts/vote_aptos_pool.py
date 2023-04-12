from pathlib import Path

from sui_brownie import SuiObject, Argument, U16, NestedResult

import dola_aptos_sdk
import dola_sui_sdk
from dola_aptos_sdk import init as dola_aptos_init
from dola_sui_sdk import init as dola_sui_init
from dola_sui_sdk import load as dola_sui_load
from dola_sui_sdk import sui_project


def main():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../.."))

    governance = dola_sui_load.governance_package()
    pool_manager = dola_sui_load.pool_manager_package()
    genesis_proposal = dola_sui_load.genesis_proposal_package()

    dola_chain_id = 1
    # Init poolmanager params
    # pool_address, dola_chain_id, pool_name, dola_pool_id, pool_weight
    btc_pool_params = [list(bytes(dola_aptos_init.btc(), "ascii")), dola_chain_id, list(b"BTC"), 0, 1]
    usdt_pool_params = [list(bytes(dola_aptos_init.usdt(), "ascii")), dola_chain_id, list(b"USDT"), 1, 1]
    usdc_pool_params = [list(bytes(dola_aptos_init.usdc(), "ascii")), dola_chain_id, list(b"USDC"), 2, 1]
    aptos_pool_params = [list(bytes(dola_aptos_init.aptos(), "ascii")), dola_chain_id, list(b"APT"), 5, 1]

    dola_sui_init.create_proposal()
    sui_project.batch_transaction(
        actual_params=[governance.governance_v1.GovernanceInfo[-1],  # 0
                       dola_sui_sdk.sui_project[SuiObject.from_type(dola_sui_init.proposal())][-1],  # 1
                       pool_manager.pool_manager.PoolManagerInfo[-1],  # 2
                       btc_pool_params[0],  # 3
                       btc_pool_params[1],  # 4
                       btc_pool_params[2],  # 5
                       btc_pool_params[3],  # 6
                       btc_pool_params[4],  # 7
                       usdt_pool_params[0],  # 8
                       usdt_pool_params[1],  # 9
                       usdt_pool_params[2],  # 10
                       usdt_pool_params[3],  # 11
                       usdt_pool_params[4],  # 12
                       usdc_pool_params[0],  # 13
                       usdc_pool_params[1],  # 14
                       usdc_pool_params[2],  # 15
                       usdc_pool_params[3],  # 16
                       usdc_pool_params[4],  # 17
                       aptos_pool_params[0],  # 18
                       aptos_pool_params[1],  # 19
                       aptos_pool_params[2],  # 20
                       aptos_pool_params[3],  # 21
                       aptos_pool_params[4],  # 22
                       ],
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
    main()
