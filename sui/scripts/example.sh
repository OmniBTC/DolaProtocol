#!/bin/bash -f

. entry_funcs.sh

mine=$(sui client active-address)

# test add member
governance_governance_add_member "$GovernanceCap" "$Governance" "$mine"
