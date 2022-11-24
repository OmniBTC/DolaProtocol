#!/bin/bash

# template
# module_function package module function args
function package_module_function() {
    local args=""
    local i=0
    for arg in "$@"
    do
      ((i+=1))
      if [ "$i" -gt 2 ]
      then
        args="$args $arg"
      fi
    done

    sui client call --package "$1" --module "$2" --function "$3" --args "$args" --gas-budget 10000
}
