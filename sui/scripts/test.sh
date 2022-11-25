#!/bin/bash -f

. entry_funcs.sh

# register pool manager admin cap
#pool_manager_pool_manager_register_admin_cap "$GovernanceExternalCap"

# add governance member
#mine="0xdc1f21230999232d6cfc230c4730021683f6546f"
#governance_governance_add_member "$GovernanceCap" "$Governance" "$mine"

# create vote for external cap
#hash="SN2lu+kXGmZWIG7FbFlcWDS2zzjF/nG8tE/kODOu6d8="
#governance_governance_create_vote_external_cap "$Governance" "$hash"

# vote for external cap
# mine="0xdc1f21230999232d6cfc230c4730021683f6546f"
#sui client switch --address "$mine"
VoteExternalCap="0x57cc91bc784166ae65b8778693b38ea1f3920e8d"
