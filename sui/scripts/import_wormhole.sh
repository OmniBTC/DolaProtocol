#!/bin/bash

export WORM_PACKAGE="0xace3a101a7cfa5ccab80569d8a5ea9078bac7ba4"
export WORM_STATE="0x0d629e8259fb4fa9c15eb66a242f52429ba6c070"
export WORM_OWNER="0xe80ebf01be88b15392d282973883ee89e68f8f48"

rev=$(find ../ | grep "Move.toml" | xargs grep -h "Wormhole =" | head -1 | sed 's/.*rev = \"\(.*\)".*/\1/g')
wormhole_path=$(find ~/.move/ -path "**$rev/sui/wormhole/Move.toml")
sed -i -e "s/wormhole = .*/wormhole = \"$WORM_PACKAGE\"/" "$wormhole_path"
