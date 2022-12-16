# @Time    : 2022/12/16 15:48
# @Author  : WeiDai
# @FileName: init.py
from dola_aptos_sdk import load


def usdt():
    return f"0x1d2c5ca9299e6e6222ab126750797e18ba0bfe55cf2aa431ddfd7f2778f17ff7::coins::USDT"


def btc():
    return f"0x1d2c5ca9299e6e6222ab126750797e18ba0bfe55cf2aa431ddfd7f2778f17ff7::coins::BTC"


def aptos():
    return "0x1::aptos_coin::AptosCoin"


def bridge_pool_read_vaa(index=0):
    wormhole_bridge = load.wormhole_bridge_package()
    vaa_event = wormhole_bridge.bridge_pool.read_vaa.simulate(
        index
    )[-2]["data"]["data"]
    return vaa_event["vaa"], vaa_event["nonce"]


def main():
    test_coins = load.test_coins_package()
    test_coins.coins.initialize()

    omnipool = load.omnipool_package()
    omnipool.pool.init_pool()
    omnipool.pool.create_pool(ty_args=[usdt()])
    omnipool.pool.create_pool(ty_args=[btc()])

    wormhole_bridge = load.wormhole_bridge_package()
    wormhole_bridge.bridge_pool.initialize_wormhole()


if __name__ == "__main__":
    main()
