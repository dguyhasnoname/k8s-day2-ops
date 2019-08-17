#!/bin/bash -e
########################################################################
# This script finds all object types in a namespace and then list them #
# Author: Mukund                                                       #
# Date: 15th August 2019                                               #
# Version: 1.0                                                         #
########################################################################

NAMESPACE="$1"
FLAG="$2"

usage() {
    echo "Usage: "
    echo "./get_namespace_objects.sh -h/-help/--h           help"
    echo "./get_namespace_objects.sh <namespace>            checks limited api-resources in a namespace"
    echo "./get_namespace_objects.sh <namespace> <all>      checks all api-resources in a namespace"
    exit
}

check_namespace() {
    echo "Validating namespace $NAMESPACE ..."
    kubectl get ns/"$NAMESPACE" && echo -en "\033[0;32mNamespace $NAMESPACE found.\033[0m" && echo -n " Fetching objects in namespace $NAMESPACE..."
}

separator() {
    printf '\n%s\n' " "
}

fetch_list() {
    OUTPUT="$(kubectl -n "$NAMESPACE" get --ignore-not-found "$object")"
    if [[ "$OUTPUT" != "" ]];
    then
        separator
        echo -e "\033[0;32m$object found: \033[0m"
        echo "$OUTPUT"
    else
        echo -n " "
    fi
}

get_helm_deployments () {
    echo -e "\033[0;32mHelm releases found in $NAMESPACE: \033[0m"
    printf "%-30s %-15s %-15s\n" RELEASE_NAME STATUS DATE
    helm list --output json --tiller-namespace="$NAMESPACE" | jq -j '.Releases[]| "\(.Name),\(.Status),\(.Updated) \n"' | awk -F ',' '{ printf "%-30s %-15s %-15s\n", $1, $2, $3 }'
    separator
}

get_objects() {
    [ -z "$NAMESPACE" ]  && usage
    check_namespace
    [ "$FLAG" == "all" ] && get_all_objects && exit

    OBJECT_LIST=(pods deployments pvc services endpoints ingress jobs secrets serviceaccounts roles rolebindings resourcequotas limitranges replicasets configmaps)
    [ "$NAMESPACE" == "kube-system" ] && unset 'OBJECT_LIST[${#OBJECT_LIST[@]}-1]'

    for object in "${OBJECT_LIST[@]}";
    do
        fetch_list
    done

    separator
}

get_all_objects() {
    for object in $(kubectl api-resources --verbs=list --namespaced -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq); 
    do
        fetch_list
    done

    separator
    get_helm_deployments
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
get_objects