import yaml
from brownie import network

from dola_ethereum_sdk import DOLA_CONFIG, get_account, set_ethereum_network, config, init


def deploy():
    account = get_account()
    cur_net = network.show_active()
    print(f"Current network:{cur_net}, account:{account}")

    wormhole_address = config["networks"][cur_net]["wormhole"]
    wormhole_chainid = config["networks"][cur_net]["wormhole_chainid"]
    not_involve_fund_consistency = config["networks"][cur_net]["not_involve_fund_consistency"]
    involve_fund_consistency = config["networks"][cur_net]["involve_fund_consistency"]
    core_emitter = config["networks"][cur_net]["core_emitter"]

    dola_pool = "0x0000000000000000000000000000000000000000"

    print("deploy wormhole adapter pool...")
    # Set relayer
    wormhole_adapter_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"].deploy(
        wormhole_address,
        wormhole_chainid,
        dola_pool,
        not_involve_fund_consistency,
        involve_fund_consistency,
        21,  # sui _emitterChainId
        core_emitter,
        account.address,
        {'from': account}
    )

    print("deploy lending portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].deploy(
        wormhole_adapter_pool.address,
        {'from': account}
    )

    print("deploy system portal...")
    system_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"].deploy(
        wormhole_adapter_pool.address,
        {'from': account}
    )

    path = DOLA_CONFIG["DOLA_PROJECT_PATH"].joinpath('ethereum/brownie-config.yaml')
    with open(path, "r") as f:
        config_file = yaml.safe_load(f)

    config_file["networks"][cur_net]["wormhole_adapter_pool"]["latest"] = wormhole_adapter_pool.address
    config_file["networks"][cur_net]["lending_portal"] = lending_portal.address
    config_file["networks"][cur_net]["system_portal"] = system_portal.address
    config_file["networks"][cur_net]["dola_pool"] = wormhole_adapter_pool.dolaPool()
    print("dolaPool", wormhole_adapter_pool.dolaPool())

    if "test" in cur_net:
        wbtc = deploy_token("WBTC")

        usdt = deploy_token("USDT")

        usdc = deploy_token("USDC")

        config_file["networks"][cur_net]["wbtc"] = wbtc.address
        config_file["networks"][cur_net]["usdt"] = usdt.address
        config_file["networks"][cur_net]["usdc"] = usdc.address

    with open(path, "w") as f:
        yaml.safe_dump(config_file, f)

def deploy_bool_adapter(dola_pool = "0x0000000000000000000000000000000000000000"):
    account = get_account()
    cur_net = network.show_active()
    print(f"Current network:{cur_net}, account:{account}")

    src_bool_anchor = config["networks"][cur_net]["src_bool_anchor"]
    src_dola_chainid = config["networks"][cur_net]["src_dola_chainid"]
    dst_bool_chainid = config["networks"][cur_net]["dst_bool_chainid"]


    print(f"deploy bool adapter pool: src_bool_anchor={src_bool_anchor}")
    bool_adapter_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["BoolAdapterPool"].deploy(
        src_bool_anchor,
        src_dola_chainid,
        dola_pool,
        account.address,
        dst_bool_chainid,
        {'from': account}
    )
    dolaPool = str(bool_adapter_pool.dolaPool())
    print(f"dolaPool={dolaPool}")

    print("deploy LibBoolAdapterVerify...")
    lib_bool_adapter_verify = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LibBoolAdapterVerify"].deploy(
        {'from': account}
    )
    print(f"lib_bool_adapter_verify={lib_bool_adapter_verify}")

    print("deploy lending_bool portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortalBool"].deploy(
        bool_adapter_pool.address,
        {'from': account}
    )

    print("deploy system_bool portal...")
    system_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortalBool"].deploy(
        bool_adapter_pool.address,
        {'from': account}
    )

    path = DOLA_CONFIG["DOLA_PROJECT_PATH"].joinpath('ethereum/brownie-config.yaml')
    with open(path, "r") as f:
        config_file = yaml.safe_load(f)

    config_file["networks"][cur_net]["bool_adapter_pool"] = {
        "latest": bool_adapter_pool.address
    }
    config_file["networks"][cur_net]["lending_portal_bool"] = lending_portal.address
    config_file["networks"][cur_net]["system_portal_bool"] = system_portal.address
    config_file["networks"][cur_net]["dola_pool"] = dolaPool


    if "test" in cur_net:
        wbtc = deploy_token("WBTC")

        usdt = deploy_token("USDT")

        usdc = deploy_token("USDC")

        config_file["networks"][cur_net]["wbtc"] = wbtc.address
        config_file["networks"][cur_net]["usdt"] = usdt.address
        config_file["networks"][cur_net]["usdc"] = usdc.address

    with open(path, "w") as f:
        yaml.safe_dump(config_file, f)


def redeploy():
    account = get_account()
    cur_net = network.show_active()
    print(f"Current network:{cur_net}, account:{account}")

    wormhole_address = config["networks"][cur_net]["wormhole"]
    wormhole_chainid = config["networks"][cur_net]["wormhole_chainid"]
    not_involve_fund_consistency = config["networks"][cur_net]["not_involve_fund_consistency"]
    involve_fund_consistency = config["networks"][cur_net]["involve_fund_consistency"]
    core_emitter = config["networks"][cur_net]["core_emitter"]

    dola_pool = init.get_dola_pool()
    print(f"init dola pool: {dola_pool}")

    print("deploy wormhole adapter pool...")
    # Set relayer
    wormhole_adapter_pool = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"].deploy(
        wormhole_address,
        wormhole_chainid,
        dola_pool,
        not_involve_fund_consistency,
        involve_fund_consistency,
        21,  # sui _emitterChainId
        core_emitter,
        account.address,
        {'from': account}
    )

    print("deploy lending portal...")
    lending_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].deploy(
        wormhole_adapter_pool.address,
        {'from': account}
    )

    print("deploy system portal...")
    system_portal = DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"].deploy(
        wormhole_adapter_pool.address,
        {'from': account}
    )
    return wormhole_adapter_pool, lending_portal, system_portal


def deploy_token(token_name="USDT"):
    account = get_account()

    print(f"deploy test token {token_name}...")
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"].deploy(
        token_name, token_name, {'from': account}
    )

if __name__ == "__main__":
    set_ethereum_network("base-main")
    deploy()
