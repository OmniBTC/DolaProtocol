
from brownie import DiamondCutFacet, DiamondLoupeFacet, GovernanceFacet, OwnershipFacet, WormholeFacet, OmniPool, DolaDiamond
from brownie import Contract
from brownie import network
from brownie.network import priority_fee
from scripts.helpful_scripts import get_account, get_method_signature_by_abi, zero_address


def main():
    if network.show_active() in ["rinkeby", "goerli"]:
        priority_fee("1 gwei")
    account = get_account()
    dola_diamond = DolaDiamond[-1]
    try:
        initialize_cut(account, dola_diamond)
    except Exception as e:
        print(f"initialize_cut failed: {e}")
    try:
        add_pool_for_wormhole_facet(account, dola_diamond)
    except Exception as e:
        print(f"add pool failed: {e}")


def initialize_cut(account, dola_diamond):
    proxy_cut = Contract.from_abi(
        "DiamondCutFacet", dola_diamond.address, DiamondCutFacet.abi)
    register_funcs = {}
    register_contract = [DiamondLoupeFacet, OwnershipFacet,
                         WormholeFacet, GovernanceFacet]
    register_data = []
    for reg in register_contract:
        print(f"Initialize {reg._name}...")
        reg_facet = reg[-1]
        reg_funcs = get_method_signature_by_abi(reg.abi)
        for func_name in list(reg_funcs.keys()):
            if func_name in register_funcs:
                if reg_funcs[func_name] in register_funcs[func_name]:
                    print(f"function:{func_name} has been register!")
                    del reg_funcs[func_name]
                else:
                    register_funcs[func_name].append(reg_funcs[func_name])
            else:
                register_funcs[func_name] = [reg_funcs[func_name]]
        register_data.append([reg_facet, 0, list(reg_funcs.values())])
    proxy_cut.diamondCut(register_data,
                         zero_address(),
                         b'',
                         {'from': account}
                         )


def add_pool_for_wormhole_facet(account, dola_diamond):
    wormhole_facet = Contract.from_abi(
        "WormholeFacet", dola_diamond.address, WormholeFacet.abi)
    wormhole_facet.addOmniPool(OmniPool[-1].address, {'from': account})
    wormhole_facet.addOmniPool(OmniPool[-2].address, {'from': account})
