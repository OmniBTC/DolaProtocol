# @Time    : 2022/12/16 18:24
# @Author  : WeiDai
# @FileName: init_ethereum_pool.py
from pathlib import Path

import dola_ethereum_sdk
import dola_sui_sdk
from dola_ethereum_sdk import init as dola_ethereum_init
from dola_sui_sdk import init as dola_sui_init


def main(pool_id, pool_name):
    dst_chain = dola_ethereum_init.get_wormhole_chain_id()

    dola_sui_init.create_proposal()
    dola_sui_init.vote_register_new_pool(
        0, b"BTC", dola_ethereum_init.btc(), dst_chain)

    dola_sui_init.create_proposal()
    dola_sui_init.vote_register_new_pool(
        1, b"USDT", dola_ethereum_init.usdt(), dst_chain)

    dola_sui_init.create_proposal()
    dola_sui_init.vote_register_new_pool(
        2, b"USDC", dola_ethereum_init.usdc(), dst_chain)

    # dola_sui_init.create_proposal()
    # dola_sui_init.vote_register_new_pool(
    #     3, b"ETH", dola_ethereum_init.eth(), dst_chain)

    dola_sui_init.create_proposal()
    dola_sui_init.vote_register_new_pool(
        pool_id, pool_name, dola_ethereum_init.eth(), dst_chain)

    # dola_sui_init.create_proposal()
    # dola_sui_init.vote_register_new_pool(
    #     6, b"BNB", dola_ethereum_init.eth(), dst_chain)


if __name__ == "__main__":
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    dola_ethereum_sdk.set_ethereum_network("polygon-test")
    main(4, b"MATIC")
    # dola_ethereum_sdk.set_ethereum_network("polygon-zk-test")
    # main(3, b"ETH")
    # dola_ethereum_sdk.set_ethereum_network("bsc-test")
    # main(6, b"BNB")
