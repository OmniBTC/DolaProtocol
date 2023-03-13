from pathlib import Path

import dola_aptos_sdk
import dola_aptos_sdk.init as dola_aptos_init
import dola_ethereum_sdk
import dola_ethereum_sdk.init as dola_ethereum_init
import dola_sui_sdk
import dola_sui_sdk.init as dola_sui_init


def remote_gov_test():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../../"))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network("polygon-test")

    sui_dola_chain_id = 0
    aptos_dola_chain_id = 1
    ethereum_dola_chain_id = 5

    # test sui dola pool owner
    new_owner_contract_id = 1000
    # add sui dola pool owner
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_register_owner(sui_dola_chain_id, new_owner_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_sui_init.register_owner(vaa)
    # remove sui dola pool owner
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_delete_owner(sui_dola_chain_id, new_owner_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_sui_init.delete_owner(vaa)

    # test sui dola pool spender
    new_spender_contract_id = 2000
    # add sui dola pool spender
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_register_spender(sui_dola_chain_id, new_spender_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_sui_init.register_spender(vaa)
    # remove sui dola pool spender
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_delete_spender(sui_dola_chain_id, new_spender_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_sui_init.delete_spender(vaa)

    # test aptos dola pool owner
    new_owner_contract_id = 10000
    # add aptos dola pool owner
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_register_owner(aptos_dola_chain_id, new_owner_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_aptos_init.register_owner(vaa)
    # remove aptos dola pool owner
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_delete_owner(aptos_dola_chain_id, new_owner_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_aptos_init.delete_owner(vaa)

    # test aptos dola pool spender
    new_spender_contract_id = 20000
    # add aptos dola pool spender
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_register_spender(aptos_dola_chain_id, new_spender_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_aptos_init.register_spender(vaa)
    # remove aptos dola pool spender
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_delete_spender(aptos_dola_chain_id, new_spender_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_aptos_init.delete_spender(vaa)

    # test ethereum dola pool owner
    new_owner_contract_id = 100000
    # add ethereum dola pool owner
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_register_owner(ethereum_dola_chain_id, new_owner_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_ethereum_init.register_owner(vaa)
    # remove ethereum dola pool owner
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_delete_owner(ethereum_dola_chain_id, new_owner_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_ethereum_init.delete_owner(vaa)

    # test ethereum dola pool spender
    new_spender_contract_id = 200000
    # add ethereum dola pool spender
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_register_spender(ethereum_dola_chain_id, new_spender_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_ethereum_init.register_spender(vaa)
    # remove ethereum dola pool spender
    dola_sui_init.create_proposal()
    dola_sui_init.vote_remote_delete_spender(ethereum_dola_chain_id, new_spender_contract_id)
    (vaa, _) = dola_sui_init.bridge_core_read_vaa()
    dola_ethereum_init.delete_spender(vaa)


if __name__ == '__main__':
    remote_gov_test()
