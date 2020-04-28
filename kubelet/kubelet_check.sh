#!/bin/bash
#######################################################################
# This script gives status of kubelt on each nodes of a cluster       #
# KUBECONFIG needs to be exported as env before running the script    #
# Author: Mukund                                                      #
# Date: 28th April 2020                                               #
#######################################################################

BOLD='\033[1;30m'
END='\033[0m'

separator() {
    printf '\n'
}

indent () {
    x="$1"
    awk '{printf "%"'"$x"'"s%s\n", "", $0}'
}

get_nodes() {
    NODES="$(kubectl get nodes -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}')"
}

get_status() {
    get_nodes
    while read -r line;
    do
        separator
        echo -e "${BOLD}kubelet status of node $line:\n${END}"
        kubectl get node "$line" \
        -o=jsonpath='{range .status.conditions[*]}{.message}{"\n"}{end}' | indent 8
    done <<< "$NODES"
}

get_status