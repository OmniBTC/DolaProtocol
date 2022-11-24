#!/bin/bash -f

. env.sh

# template
# module_function package module function args
function package_module_function() {
    args=($(get_args "$@"))
    sui client call --package "$package" --module "module" --function "function" --gas-budget 10000 --args "${args[@]}"
}

function get_args() {
    local args=""
    local i=0
    for arg in "$@"
    do
      args="$args $arg"
    done
    echo "$args"
}
