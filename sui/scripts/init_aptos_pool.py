# @Time    : 2022/12/16 18:24
# @Author  : WeiDai
# @FileName: init_aptos_pool.py
from dola_sui_sdk import init as dola_sui_init
from dola_aptos_sdk import init as dola_aptos_init


def main():
    # init pool manager
    hash = dola_sui_init.register_pool_manager_admin_cap()
    dola_sui_init.create_vote_external_cap(hash)
    dola_sui_init.vote_pool_manager_cap_proposal()

    dola_sui_init.create_vote_external_cap(hash)
    dola_sui_init.vote_register_new_pool_proposal(0, b"BTC", dola_aptos_init.btc())

    dola_sui_init.create_vote_external_cap(hash)
    dola_sui_init.vote_register_new_pool_proposal(1, b"USDT", dola_aptos_init.usdt())


if __name__ == "__main__":
    main()
