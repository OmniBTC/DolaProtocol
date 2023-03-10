# @Time    : 2022/12/16 15:48
# @Author  : WeiDai
# @FileName: init.py
from dola_aptos_sdk import load


def usdt():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::USDT"


def usdc():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::USDC"


def btc():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::BTC"


def eth():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::ETH"


def dai():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::DAI"


def matic():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::MATIC"


def bnb():
    test_coins = load.test_coins_package()
    return f"{test_coins.network_config['replace_address']['test_coins']}::coins::BNB"


def aptos():
    return "0x1::aptos_coin::AptosCoin"


def bridge_pool_read_vaa(index=0):
    omnipool = load.omnipool_package()
    vaa_event = omnipool.wormhole_adapter_pool.read_vaa.simulate(
        index
    )[-2]["data"]["data"]
    return vaa_event["vaa"], vaa_event["nonce"]


def main():
    test_coins = load.test_coins_package()
    test_coins.coins.initialize()

    dola_types = load.dola_types_package()
    dola_types.dola_contract.init()

    omnipool = load.omnipool_package()
    omnipool.dola_pool.init()
    omnipool.dola_pool.create_pool(ty_args=[usdt()])
    omnipool.dola_pool.create_pool(ty_args=[btc()])
    omnipool.dola_pool.create_pool(ty_args=[usdc()])
    omnipool.dola_pool.create_pool(ty_args=[aptos()])
    omnipool.wormhole_adapter_pool.init(0, str(omnipool.account.account_address))

    dola_portal = load.dola_portal_package()
    dola_portal.lending.init()
    dola_portal.system.init()


if __name__ == "__main__":
    main()
