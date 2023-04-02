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


def aptos():
    return "0x1::aptos_coin::AptosCoin"


def register_owner(vaa):
    omnipool = load.omnipool_package()
    omnipool.wormhole_adapter_pool.register_owner(vaa)


def register_spender(vaa):
    omnipool = load.omnipool_package()
    omnipool.wormhole_adapter_pool.register_spender(vaa)


def delete_owner(vaa):
    omnipool = load.omnipool_package()
    omnipool.wormhole_adapter_pool.delete_owner(vaa)


def delete_spender(vaa):
    omnipool = load.omnipool_package()
    omnipool.wormhole_adapter_pool.delete_spender(vaa)


def bridge_pool_read_vaa(index=0):
    omnipool = load.omnipool_package()
    vaa_event = omnipool.wormhole_adapter_pool.read_vaa.simulate(
        index
    )[-2]["data"]["data"]
    return vaa_event["vaa"], vaa_event["nonce"]


def calculate_resource_address():
    dola_portal = load.dola_portal_package()
    print(dola_portal.account.account_address)
    resource_addr = dola_portal.get_resource_addr(str(dola_portal.account.account_address), "Dola Lending Portal")
    print(resource_addr)


def lending_portal_relay_events(limit=5):
    dola_portal = load.dola_portal_package()
    resource_addr = dola_portal.get_resource_addr(str(dola_portal.account.account_address), "Dola Lending Portal")
    events = dola_portal.get_events(
        resource_addr,
        f"{str(dola_portal.account.account_address)}::lending::LendingPortal",
        "relay_event_handle",
        limit,
    )
    return [event['data'] for event in events]


def system_portal_relay_events(limit=5):
    dola_portal = load.dola_portal_package()
    resource_addr = dola_portal.get_resource_addr(str(dola_portal.account.account_address), "Dola System Portal")
    events = dola_portal.get_events(
        resource_addr,
        f"{str(dola_portal.account.account_address)}::system::SystemPortal",
        "relay_event_handle",
        limit,
    )
    return [event['data'] for event in events]


def relay_events(limit=5):
    lending_relay_events = lending_portal_relay_events(limit)
    system_relay_events = system_portal_relay_events(limit)
    return lending_relay_events + system_relay_events


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
