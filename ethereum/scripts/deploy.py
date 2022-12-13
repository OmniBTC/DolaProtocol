from brownie import OmniPool, LendingPortal, MockToken, DiamondCutFacet, DiamondLoupeFacet, GovernanceFacet, \
    OwnershipFacet, WormholeFacet, DolaDiamond

from brownie import network
from brownie.network import priority_fee

from scripts.helpful_scripts import get_account, get_wormhole, get_wormhole_chain_id, zero_address


def deploy():
    account = get_account()
    if network.show_active() in ["rinkeby", "goerli"]:
        priority_fee("1 gwei")
    deploy_facets = [DiamondCutFacet, DiamondLoupeFacet, GovernanceFacet,
                     OwnershipFacet, WormholeFacet]
    for facet in deploy_facets:
        print(f"deploy {facet._name}...")
        facet.deploy({'from': account})

    print("deploy DolaDiamond...")
    DolaDiamond.deploy(account.address, DiamondCutFacet[-1], [get_wormhole(
    ), get_wormhole_chain_id(), 1, zero_address()], {'from': account})

    deploy_omnipool("USDT", account)
    deploy_omnipool("BTC", account)

    print("deploy LendingPortal...")
    LendingPortal.deploy(DolaDiamond[-1], {'from': account})


def deploy_omnipool(token, account):
    print(f"deploy {token}...")
    MockToken.deploy(token, token, {'from': account})
    print(f"deploy {token} omnipool...")
    OmniPool.deploy(DolaDiamond[-1].address,
                    MockToken[-1].address, {'from': account})
