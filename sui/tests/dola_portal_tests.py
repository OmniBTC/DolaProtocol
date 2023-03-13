from pathlib import Path

import dola_aptos_sdk
import dola_aptos_sdk.init as dola_aptos_init
import dola_aptos_sdk.lending as dola_aptos_portal
import dola_ethereum_sdk
import dola_ethereum_sdk.init as dola_ethereum_init
import dola_ethereum_sdk.lending as dola_ethereum_portal
import dola_sui_sdk
import dola_sui_sdk.init as dola_sui_init
import dola_sui_sdk.lending as dola_sui_portal


def zero_address():
    return "0x0000000000000000000000000000000000000000"


def dola_portal_test():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../../"))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network("polygon-test")

    # test sui portal
    # test sui supply
    dola_sui_init.claim_test_coin(dola_sui_init.btc())
    dola_sui_portal.portal_supply(dola_sui_init.btc())

    # test sui bind and unbind
    dola_sui_portal.portal_binding(zero_address())
    dola_sui_portal.portal_unbinding(zero_address())

    # test sui manage collateral
    dola_sui_portal.portal_cancel_as_collateral([0])
    dola_sui_portal.portal_as_collateral([0])

    # test sui withdraw
    dola_sui_portal.portal_withdraw_local(dola_sui_init.btc(), 1e8)

    # test aptos portal
    # test aptos supply
    dola_aptos_portal.claim_test_coin(dola_aptos_init.usdt())
    vaa = dola_aptos_portal.portal_supply(dola_aptos_init.usdt(), 1e8)
    dola_sui_portal.core_supply(vaa)

    # test aptos bind and unbind
    vaa = dola_aptos_portal.portal_binding(zero_address())
    dola_sui_portal.core_binding(vaa)
    vaa = dola_aptos_portal.portal_unbinding(zero_address())
    dola_sui_portal.core_unbinding(vaa)

    # test aptos manage collateral
    vaa = dola_aptos_portal.portal_cancel_as_collateral([1])
    dola_sui_portal.core_cancel_as_collateral(vaa)
    vaa = dola_aptos_portal.portal_as_collateral([1])
    dola_sui_portal.core_as_collateral(vaa)

    # test aptos withdraw
    vaa = dola_aptos_portal.portal_withdraw(dola_aptos_init.usdt(), 1e8)
    dola_sui_portal.core_withdraw(vaa)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_aptos_portal.pool_withdraw(vaa, dola_aptos_init.usdt())

    # test ethereum portal
    # test ethereum supply
    dola_ethereum_portal.portal_supply(dola_ethereum_init.usdc(), 1e18)
    vaa = dola_ethereum_init.bridge_pool_read_vaa()
    dola_sui_portal.core_supply(vaa)

    # test ethereum bind and unbind
    dola_ethereum_portal.portal_binding(zero_address())
    vaa = dola_ethereum_init.bridge_pool_read_vaa()
    dola_sui_portal.core_binding(vaa)
    dola_ethereum_portal.portal_unbinding(zero_address())
    vaa = dola_ethereum_init.bridge_pool_read_vaa()
    dola_sui_portal.core_unbinding(vaa)

    # test ethereum manage collateral
    dola_ethereum_portal.portal_cancel_as_collateral([1])
    vaa = dola_ethereum_init.bridge_pool_read_vaa()
    dola_sui_portal.core_cancel_as_collateral(vaa)
    dola_ethereum_portal.portal_as_collateral([1])
    vaa = dola_ethereum_init.bridge_pool_read_vaa()
    dola_sui_portal.core_as_collateral(vaa)

    # test ethereum withdraw
    dola_ethereum_portal.portal_withdraw(dola_ethereum_init.usdc(), 1e8)
    vaa = dola_ethereum_init.bridge_pool_read_vaa()
    dola_sui_portal.core_withdraw(vaa)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_ethereum_portal.pool_withdraw(vaa)


if __name__ == '__main__':
    dola_portal_test()
