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
