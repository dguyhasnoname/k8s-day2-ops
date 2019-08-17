#!/bin/bash
#######################################################################
# This script gives status of kubelt on each nodes of a cluster       #
# KUBECONFIG needs to be exported as env before running the script    #
# Author: Mukund                                                      #
# Date: 17th August 2019                                              #
# Version: 1.0                                                        #
#######################################################################

separator() {
    printf "===========================================\n"
}

get_nodes() {
    kubectl get nodes --no-headers | awk '{print $1}' > NODES
}

get_status() {
    get_nodes
    while read -r line;
    do
        separator
        printf "kubelet status of node $line\n"
        echo "-------------------------------------------"
        kubectl get node "$line" -o json| jq '.status.conditions[].message'
    done < "NODES"
}

get_status