#!/bin/bash
##########################################################################
# This script finds all object types in a namespace and then lists them. #
# Author: Mukund                                                         #
# Date: 15th August 2019                                                 #
# Version: 1.0                                                           #
##########################################################################

NAMESPACE="${1:-kube-system}"
FLAG="$2"

[ "$(echo $KUBECONFIG)" == "" ] && echo "Please set KUBECONFIG for the cluster." && exit

usage() {
    echo "[WARNING]: Export KUBECONFIG before running the script."
    echo "Usage: "
    echo "./get_namespace_objects.sh -h/-help/--h           help"
    echo "./get_namespace_objects.sh <namespace>            checks limited api-resources and OpenEBS PVC and PV in a namespace"
    echo "./get_namespace_objects.sh <namespace> <-v>       checks all api-resources and openEBS objects in a namespace"
    exit
}

#Validates namespace name
check_namespace() {
    echo "Validating namespace $NAMESPACE ..."
    kubectl get ns/"$NAMESPACE" && echo -en "\033[0;32mNamespace $NAMESPACE found.\033[0m" && echo -n " Fetching objects in namespace $NAMESPACE..."
    [ ! $? -eq 0 ] && echo  "[ERROR]: Namespace $NAMESPACE was not found! Please provide correct namespace." && exit
}

separator() {
    printf '\n%s\n' " "
}

#list resources for a object type like pods, secrets etc.
fetch_list() {
    OUTPUT="$(kubectl -n "$NAMESPACE" get --ignore-not-found "$object")"
    if [[ "$OUTPUT" != "" ]];
    then
        if [[ "$FLAG" != "" && "$object" == "persistentvolumeclaims" ]];
        then
             echo ""
        else
            separator
            echo -e "\033[0;32m$object found: \033[0m"
            echo "$OUTPUT"
        fi
    else
        echo -n " "
    fi
}

get_openebs_objects () {
    separator
    echo -e "\033[0;32mOpenEBS PVCs found in $NAMESPACE: \033[0m"
    kubectl get pvc -n "$NAMESPACE"
    separator

    echo -e "\033[0;32mOpenEBS PVs found in $NAMESPACE: \033[0m"
    kubectl get pv | grep -i "$NAMESPACE"

    BOUND_PVC="$(kubectl get  pv | grep -i "$NAMESPACE" | grep Bound | grep cstor | awk '{print $1}')"

    if [[ "$BOUND_PVC" != "" && "$FLAG" == "all" ]];
    then
        separator
        echo -e "\033[0;32mOpenEBS cstorVolumes found in $NAMESPACE for pvc $line : \033[0m"
        while read -r line;
        do
            kubectl get cstorvolumes -A | grep -i "$line"
        done <<< "$BOUND_PVC"

        separator
        echo -e "\033[0;32mOpenEBS cstorVolumeReplicas found in $NAMESPACE: \033[0m"
        while read -r line;
        do
            kubectl get cvr  -A | grep -i "$line"
        done <<< "$BOUND_PVC"
    else
        separator
        exit
    fi
}

#get helm deployments
get_helm_deployments () {
    CHECK_RELEASE="$(helm list --tiller-namespace="$NAMESPACE")"
    echo -e "\033[0;32mHelm releases found in $NAMESPACE: \033[0m"
    printf "%-30s %-15s %-15s\n" RELEASE_NAME STATUS DATE
    helm list --output json --tiller-namespace="$NAMESPACE" | jq -j '.Releases[]| "\(.Name),\(.Status),\(.Updated) \n"' | awk -F ',' '{ printf "%-30s %-15s %-15s\n", $1, $2, $3 }'
    separator
}

#gets the list of resources for few important objects
get_objects() {
    [ -z "$NAMESPACE" ]  && usage
    check_namespace
    [ "$FLAG" == "-v" ] && get_all_objects && exit

    OBJECT_LIST=(pods deployments statefulsets services endpoints ingress hpa jobs secrets serviceaccounts roles rolebindings resourcequotas limitranges replicasets configmaps)
    [ "$NAMESPACE" == "kube-system" ] && unset 'OBJECT_LIST[${#OBJECT_LIST[@]}-1]'

    for object in "${OBJECT_LIST[@]}";
    do
        fetch_list
    done
    get_openebs_objects
    separator
}

#gets the list of resources for all objects and lists helm deployments too.
get_all_objects() {
    for object in $(kubectl api-resources --verbs=list --namespaced -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq);
    do
        fetch_list
    done

    get_openebs_objects
    separator
    get_helm_deployments
    separator
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
get_objects