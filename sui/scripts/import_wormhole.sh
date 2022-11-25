#!/bin/bash

export WORM_PACKAGE="0x464f7e4644b6cc807757340129de0be0630f1c22"
export WORM_STATE="0x027a87ae1855d9769a89ac7027f1644a45408fd8"
export WORM_OWNER="0xe80ebf01be88b15392d282973883ee89e68f8f48"

rev=$(find ../ | grep "Move.toml" | xargs grep -h "Wormhole =" | head -1 | sed 's/.*rev = \"\(.*\)".*/\1/g')
wormhole_path=$(find ~/.move/ -path "**$rev/sui/wormhole/Move.toml")
sed -i -e "s/wormhole = .*/wormhole = \"$WORM_PACKAGE\"/" "$wormhole_path"
