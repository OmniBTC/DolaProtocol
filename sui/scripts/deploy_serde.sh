#!/bin/bash

# serde as a tool library only needs to be deployed once

find ../ | grep "Move.toml" | xargs sed -i -e 's/serde = .*/serde = "0x0"/'

#Transaction Kind : Publish
#----- Transaction Effects ----
#Status : Success
#Created Objects:
#  - ID: 0x2653e605c5e0fc39d364b51c39f3dafab62c8cdd , Owner: Immutable
#Mutated Objects:
#  - ID: 0x6466c1fd1803230a3f1e7637c82c080d8f18ee08 , Owner: Account Address ( 0xe80ebf01be88b15392d282973883ee89e68f8f48 )

sui client publish -p ../serde --gas-budget 10000 | tee publish.log
grep ID: publish.log  | head -2 > ids.log
serde="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/serde = .*/serde = \"$serde\"/"
