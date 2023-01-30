# @Time    : 2022/12/16 18:24
# @Author  : WeiDai
# @FileName: init_aptos_pool.py
from pathlib import Path

import dola_aptos_sdk
from dola_aptos_sdk import init as dola_aptos_init

import dola_sui_sdk
from dola_sui_sdk import init as dola_sui_init


def main():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../.."))

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        0, b"BTC", dola_aptos_init.btc(), dst_chain=1)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        1, b"USDT", dola_aptos_init.usdt(), dst_chain=1)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        2, b"USDC", dola_aptos_init.usdc(), dst_chain=1)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        6, b"APT", dola_aptos_init.aptos(), dst_chain=1)


if __name__ == "__main__":
    main()
