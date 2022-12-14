# @Time    : 2022/12/16 18:24
# @Author  : WeiDai
# @FileName: init_aptos_pool.py
from pathlib import Path

import dola_aptos_sdk
from dola_aptos_sdk import init as dola_aptos_init

import dola_sui_sdk
from dola_sui_sdk import init as dola_sui_init
from dola_sui_sdk import load as dola_sui_load


def main():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../.."))

    # init pool manager
    governance = dola_sui_load.governance_package()
    governance_external_cap = governance.get_object_with_super_detail(
        governance.governance.GovernanceExternalCap[-1])
    governance_external_hash = ""
    for d in governance_external_cap["dynamic_field"]:
        if "governance_external" in d.value:
            governance_external_hash = d.name

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        0, b"BTC", dola_aptos_init.btc(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        1, b"USDT", dola_aptos_init.usdt(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        2, b"USDC", dola_aptos_init.usdc(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        3, b"ETH", dola_aptos_init.eth(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        4, b"DAI", dola_aptos_init.dai(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        5, b"MATIC", dola_aptos_init.matic(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        6, b"APT", dola_aptos_init.aptos(), dst_chain=1)

    dola_sui_init.create_vote_external_cap(governance_external_hash)
    dola_sui_init.vote_register_new_pool(
        7, b"BNB", dola_aptos_init.bnb(), dst_chain=1)


if __name__ == "__main__":
    main()
