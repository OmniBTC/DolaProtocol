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

    dst_chain = dola_ethereum_init.get_wormhole_chain_id()

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        0, b"BTC", dola_ethereum_init.btc_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        1, b"USDT", dola_ethereum_init.usdt_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        2, b"USDC", dola_ethereum_init.usdc_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        3, b"ETH", dola_ethereum_init.eth_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        4, b"DAI", dola_ethereum_init.dai_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        5, b"MATIC", dola_ethereum_init.matic_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        6, b"APT", dola_ethereum_init.apt_pool(), dst_chain)

    dola_sui_init.create_vote_external_cap()
    dola_sui_init.vote_register_new_pool(
        7, b"BNB", dola_ethereum_init.bnb_pool(), dst_chain)


if __name__ == "__main__":
    dola_ethereum_sdk.set_ethereum_network("polygon-zk-test")
    main()
