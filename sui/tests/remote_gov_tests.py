from pathlib import Path

import dola_aptos_sdk
import dola_ethereum_sdk
import dola_sui_sdk
import dola_sui_sdk.init as dola_sui_init

bind_address = "0x0000000000000000000000000000000000000000"


def remote_gov_test():
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_aptos_sdk.set_dola_project_path(Path("../../"))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network("polygon-test")

    sui_dola_chain_id = 0

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


if __name__ == '__main__':
    remote_gov_test()
