#!/bin/bash -f

# Deploy using sui command line tool

 import wormhole
. import_wormhole.sh
find ../ | grep "Move.toml" | xargs sed -i -e "s/wormhole = .*/wormhole = \"$WORM_PACKAGE\"/"

# 1. deploy omnipool

find ../ | grep "Move.toml" | xargs sed -i -e 's/omnipool = .*/omnipool = "0x0"/'

sui client publish -p ../omnipool --gas-budget 10000 | tee publish.log
grep ID: publish.log  | head -2 > ids.log
omnipool="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/omnipool = .*/omnipool = \"$omnipool\"/"

# 2. deploy app_manager

find ../ | grep "Move.toml" | xargs sed -i -e 's/app_manager = .*/app_manager = "0x0"/'

sui client publish -p ../omnicore/app_manager --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -3 > ids.log
app_manager="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
TotalAppInfo="$(grep "Shared" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
AppManagerCap="$(grep "Account Address" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/app_manager = .*/app_manager = \"$app_manager\"/"

# 3. deploy governance

find ../ | grep "Move.toml" | xargs sed -i -e 's/governance = .*/governance = "0x0"/'

sui client publish -p ../omnicore/governance --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -4 > ids.log
governance="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
shared="$(grep "Shared" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
shared_array=(${shared//\n/})
Governance=${shared_array[0]}
GovernanceExternalCap=${shared_array[1]}
GovernanceCap="$(grep "Account Address" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/governance = .*/governance = \"$governance\"/"

# 4. deploy oracle

find ../ | grep "Move.toml" | xargs sed -i -e 's/oracle = .*/oracle = "0x0"/'

sui client publish -p ../omnicore/oracle --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -3 > ids.log
oracle="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
PriceOracle="$(grep "Shared" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
OracleCap="$(grep "Account Address" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/oracle = .*/oracle = \"$oracle\"/"

# 5. deploy pool_manager

find ../ | grep "Move.toml" | xargs sed -i -e 's/pool_manager = .*/pool_manager = "0x0"/'

sui client publish -p ../omnicore/pool_manager --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -2 > ids.log
pool_manager="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
PoolManagerInfo="$(grep "Shared" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/pool_manager = .*/pool_manager = \"$pool_manager\"/"

# 6. deploy wormhole_bridge

find ../ | grep "Move.toml" | xargs sed -i -e 's/wormhole_bridge = .*/wormhole_bridge = "0x0"/'

sui client publish -p ../wormhole_bridge --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -1 > ids.log
wormhole_bridge="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/wormhole_bridge = .*/wormhole_bridge = \"$wormhole_bridge\"/"

# 7. deploy lending

find ../ | grep "Move.toml" | xargs sed -i -e 's/lending = .*/lending = "0x0"/'

sui client publish -p ../omnicore/lending --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -3 > ids.log
lending="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
shared="$(grep "Shared" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
shared_array=(${shared//\n/})
Storage=${shared_array[0]}
WormholeAdapater=${shared_array[1]}
find ../ | grep "Move.toml" | xargs sed -i -e "s/lending = .*/lending = \"$lending\"/"

# 8. deploy lending_portal

find ../ | grep "Move.toml" | xargs sed -i -e 's/lending_portal = .*/lending_portal = "0x0"/'

sui client publish -p ../lending_portal --gas-budget 10000 | tee publish.log
grep ID: publish.log | head -1 > ids.log
lending_portal="$(grep "Immutable" ids.log | sed -e 's/^.*: \(.*\) ,.*/\1/')"
find ../ | grep "Move.toml" | xargs sed -i -e "s/lending_portal = .*/lending_portal = \"$lending_portal\"/"

# export

echo "export wormhole=\"$WORM_PACKAGE\"" > ./env.sh
{
  echo "export State=\"$WORM_STATE\"" 
  echo "export omnipool=\"$omnipool\""
  echo "export app_manager=\"$app_manager\""
  echo "export TotalAppInfo=\"$TotalAppInfo\"" 
  echo "export AppManagerCap=\"$AppManagerCap\""
  echo "export governance=\"$governance\"" 
  echo "export Governance=\"$Governance\"" 
  echo "export GovernanceExternalCap=\"$GovernanceExternalCap\"" 
  echo "export GovernanceCap=\"$GovernanceCap\"" 
  echo "export oracle=\"$oracle\"" 
  echo "export PriceOracle=\"$PriceOracle\"" 
  echo "export OracleCap=\"$OracleCap\"" 
  echo "export pool_manager=\"$pool_manager\"" 
  echo "export PoolManagerInfo=\"$PoolManagerInfo\"" 
  echo "export wormhole_bridge=\"$wormhole_bridge\""
  echo "export lending=\"$lending\""
  echo "export Storage=\"$Storage\"" 
  echo "export WormholeAdapater=\"$WormholeAdapater\""
  echo "export lending_portal=\"$lending_portal\"" 
} >> ./env.sh




