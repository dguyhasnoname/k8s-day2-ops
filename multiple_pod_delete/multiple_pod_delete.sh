#!/bin/bash
########################################################################
# This script deletes multiple pods which contains given match in a    #
# namespace. KUBECONFIG needs to be exported prior running the script  #
# Author: Mukund                                                       #
# Date: 15th August 2019                                               #
# Version: 1.0                                                         #
########################################################################

STRING="$1"
NAMESPACE="${2:-kube-system}"

usage() {
    echo "****Export KUBECONFIG before running the script.***"
    echo "Usage: "
    echo "./multiple_pod_delete.sh -h/-help/--h         help"
    echo "./multiple_pod_delete.sh <namespace>          deletes multiple pods which contains given string"
    exit
}

separator() {
    echo "----------------------------------------------------------------------------------------"
}

get_pods() {
    separator
    printf '%s\n' "Checking for pod containing string $STRING in namespace $NAMESPACE:"
    separator
    PODS="$(kubectl get pods --no-headers -n "$NAMESPACE"| grep -i "$STRING")"
    if [[ "$PODS" == "" ]];
    then
        printf '\e[1;31m%s\e[0m\n\n' "Either namespace $NAMESPACE doesn't exists OR pods with name containing string '$STRING' was not found in namespace $NAMESPACE."
        exit
    else
        printf '\e[1;32m%s\e[0m\n\n' "Below pods were found in namespace $NAMESPACE with containing string $STRING: "
        echo "$PODS"
    fi
}

delete_pods() {
    [[ "$STRING" == "-h" || "$STRING" == "--h" || "$STRING" == "-help" || -z "$STRING" ]] && usage
    get_pods
    printf '\e[1;33m%s\e[0m' "Do you want to delete the pods(Y/N):  "
    read -r  USER_INPUT
    separator
    if [[ "$USER_INPUT" == "Y" ]];
    then
        echo "Deleting pods in namespace $NAMESPACE..."
        while read -r line;
        do
            line="$(echo "$line" | awk '{print $1}')"
            kubectl delete pod "$line" -n "$NAMESPACE"
        done <<< "$PODS"
        separator
        printf '\e[1;32m%s\e[0m\n\n' "Checking pods status after deletion: "
        kubectl get pods --no-headers -n "$NAMESPACE" | grep -i "$STRING"
    else
        echo "Did not get input to delete pods."
        echo "Exiting script!"
    fi
    separator
}

delete_pods