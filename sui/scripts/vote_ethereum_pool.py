# @Time    : 2022/12/16 18:24
# @Author  : WeiDai
# @FileName: init_ethereum_pool.py
from pathlib import Path

import dola_ethereum_sdk
from dola_ethereum_sdk import init as dola_ethereum_init

import dola_sui_sdk
from dola_sui_sdk import init as dola_sui_init
from dola_sui_sdk import load as dola_sui_load


def main():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network("bsc-test")

    # init pool manager
    governance = dola_sui_load.governance_package()
    governance_external_cap = governance.get_object_with_super_detail(governance.governance.GovernanceExternalCap[-1])

    governance_external_hash = ""
    for d in governance_external_cap["dynamic_field"]:
        if "governance_external" in d.value:
            governance_external_hash = d.name

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(0, b"BTC", dola_ethereum_init.btc_pool(), dst_chain=4)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(1, b"USDT", dola_ethereum_init.usdt_pool(), dst_chain=4)


if __name__ == "__main__":
    main()
