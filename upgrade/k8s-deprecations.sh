#!/bin/bash
##########################################################################
# This script finds all deprecations in k8s apiVersion.                  #
# Author: Mukund                                                         #
# Date: 14th Jan 2021                                                    #
# Version: 2.0                                                           #
##########################################################################

START_TIME=$(date +%s)
RED='\033[1;31m'
GREEN='\033[0;32m'
BOLD='\033[1;30m'
END='\033[0m'
TICK='\xE2\x9C\x94'

verbose () {
    [ "$DEBUG" == "-v" ] && true
}

separator () {
    printf '\n'
}

indent () {
    x="$1"
    awk '{printf "%"'"$x"'"s%s\n", "", $0}'
}

usage () {
    [[ -z "$KUBECONFIG" ]] && echo "[WARNING]: Export KUBECONFIG before running the script."
    echo "Usage: "
    separator
    echo "./k8s-deprecations.sh -v 1.18.0 -n kube-system -d"
    separator
    echo "Flags:"
    echo "  -h                  help"
    echo "  -v   Mandatory      Gets all deprecations in k8s api"
    echo "  -d   Optional       Debug mode, all deprecations in k8s api alongwith objects using it"
    echo "  -n   Optional       Pass namespace name to get namespaced deprecations in k8s api alongwith objects using it"
    separator
    exit
}

get_swagger () {
    # this function complies a list of possible deprecated APIs from k8s repo
    separator
    >deprecated_apiversion
    echo "Gathering info of current cluster..."
    current_k8s_version="$(kubectl get nodes -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | uniq | sed 's/\v//g')"
    echo "Current k8s version: v$current_k8s_version"
    version="$(echo $current_k8s_version | sed 's/\(.*\)\..*/\1/').0"
    UPGRADE_PATH="v$current_k8s_version"
    while [[ "$(echo "$version "| awk -F '.' '{print $2}')" -le "$(echo "$VERSION" | awk -F '.' '{print $2}')" ]];
    do
        echo "Fetching all objects from kubenetes repo: v$version..."
        swagger_json="$(curl -s swagger-v"$version".json https://raw.githubusercontent.com/kubernetes/kubernetes/v"$version"/api/openapi-spec/swagger.json)"
        #deprecated_apiversion="$(echo "$swagger_json" | jq -r '.definitions | keys[] as $k | "\($k): \(.[$k] | .description)"' | grep -w DEPRECATED)"
        echo "$swagger_json" | jq -r '.definitions | keys[] as $k | "\($k): \(.[$k] | .description)"' | grep -i DEPRECATED >> deprecated_apiversion
        major_version="$(echo $version | awk -F '.' '{print $2}')"
        major_version=$(( $major_version+1 ))
        version="1.$(echo $major_version).0"        
    done
}

fetch_deprecated_objects () {
    # this function complies a list of possible deprecated APIs from the given cluster
    deprecated_object_kind="$1"
    if [[ -z "$NAMESPACE" ]];
    then
        deprecated_object_json="$(kubectl get $deprecated_object_kind -A -o json)"
    else
        deprecated_object_json="$(kubectl get $deprecated_object_kind -n $NAMESPACE -o json)"
    fi

    deprecated_apiversion_list="$(echo "$DEPRECATED_LIST" | grep -w "$deprecated_object_kind" | awk -F ':' '{print $2}' | uniq)"

    while read -r line;
    do
        deprecated_object_list="$(echo "$deprecated_object_json" | jq -rj '.items[] | select(.apiVersion | contains("'$line'")) | .metadata.namespace, ": ",.metadata.name,"\n"')"
        if [[ $? -eq 0 && -z "$deprecated_object_list" ]];
        then
            echo -e "${GREEN}${TICK} 0 $deprecated_object_kind using deprecated apiVersion: $line${END}" | indent 10
        else
            echo -e "${RED}Deprecated $deprecated_object_kind found using deprecated apiVersion: $line${END}" | indent 10
            if verbose;
            then
                separator
                printf "NAMESPACE%37s\n" $deprecated_object_kind | indent 10
                echo -e "$deprecated_object_list" | awk -F":" '{printf("%-35s%-20s\n", $1, $2)}' | indent 10
            fi
        fi
    done <<< "$deprecated_apiversion_list"
}

main () {
    [ "$KUBECONFIG" == "" ] && echo -e "${RED}Please set KUBECONFIG for the cluster.${END}" && exit
    [[ ! -z "$NAMESPACE" ]] && ! kubectl get ns "$NAMESPACE" && exit
    get_swagger
    separator
    echo -e "${RED}Below is the list of deprecated apiVersion which may impact objects in cluster: ${END}"
    separator

    DEPRECATED_LIST="$(cat deprecated_apiversion | awk -F ':' '{print $1}' | grep -v DEPRECATED | awk -F '.' '{print $NF":",$(NF-2)"/"$(NF-1)}' | sort | uniq)"
    deprecated_kind="$(echo "$DEPRECATED_LIST" | awk -F ':' '{print $1}' | uniq)"
    printf "K8S_OBJECT%16sAPI_VERSION\n"
    echo  "$DEPRECATED_LIST" | awk -F":" '{printf("%-25s%10s\n", $1, $2)}'
    separator

    CURRENT_API_RESOURCES="$(kubectl api-resources --no-headers)"
    checked_object_kind_list=""

    while read -r line;
    do
        separator
        checked_object_kind="$line"
        ! verbose && echo -e "Checking if ${BOLD}$line${END} kind objects exists in the cluster... "
        local apiversion="$(echo "$DEPRECATED_LIST" | grep "$line" | awk -F ':' '{print $2}' | sort | uniq)"
        if [[ "$CURRENT_API_RESOURCES" == *"$line"* && ! "$checked_object_kind_list" == *"$checked_object_kind"* ]];
        then
            #echo -e "${RED}$line kind objects found${END} which may be using deprecated apiVersion:"$apiversion""
            echo -e "${RED}$line kind objects: ${END}"
            fetch_deprecated_objects "$checked_object_kind"
            checked_object_kind_list="$checked_object_kind_list,$checked_object_kind"
        else
            echo -e "${GREEN}${TICK} $line: no deprecated objects found!${END}"
        fi
    done <<< "$deprecated_kind"
    separator
}


OPTIND=1         

while getopts "h?n:dv:o:" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
    n)  NAMESPACE=$OPTARG
        ;;    
    d)  DEBUG='-v' 
        ;;
    v)  VERSION=$OPTARG
        ;;
    o)  OBJECT=$OPTARG
        ;;        
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

[[ -z "$VERSION" ]] && \
echo "[ERROR] Missing mandatory arguments" && usage 
[ -x parallel ] && echo -e "${RED}Command 'parallel' not found. Please install it.${END}" >&2 && exit 1
[ -x jq ] && echo -e "${RED}Command 'jq' not found. Please install it.${END}" >&2 && exit 1
main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
echo "Total time taken:" "$EXECUTION_TIME"s