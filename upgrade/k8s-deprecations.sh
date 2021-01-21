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
    printf "Usage: \n\n"
    printf "./k8s-deprecations.sh -v 1.18.0 -n kube-system -d \n\n"
    echo "Flags:"
    echo "  -h                  help"
    echo "  -v   Mandatory      Gets all deprecations in k8s api"
    echo "  -d   Optional       Debug mode, all deprecations in k8s api alongwith objects using it"
    echo "  -n   Optional       Pass namespace name to get namespaced deprecations in k8s api alongwith objects using it"
    echo "  -o   Optional       Output in json format"
    separator
    exit
}

get_swagger () {
    # this function complies a list of possible deprecated APIs from k8s repo
    separator
    >deprecated_apiversion
    echo "Gathering info of current cluster..."
    set -e
    current_k8s_version="$(kubectl get nodes -o json \
    | jq -r '.items[].status.nodeInfo.kubeletVersion' | uniq | sed 's/\v//g')"
    set +e
    echo "Current k8s version: v$current_k8s_version"
    version="$(echo $current_k8s_version | sed 's/\(.*\)\..*/\1/').0"
    UPGRADE_PATH="v$current_k8s_version"
    while [[ "$(echo "$version "| awk -F '.' '{print $2}')" -le "$(echo "$VERSION" | awk -F '.' '{print $2}')" ]];
    do
        echo "Fetching all objects from kubenetes repo: v$version..."
        swagger_json="$(curl -s swagger-v"$version".json https://raw.githubusercontent.com/kubernetes/kubernetes/v"$version"/api/openapi-spec/swagger.json)"
        #deprecated_apiversion="$(echo "$swagger_json" | jq -r '.definitions | keys[] as $k | "\($k): \(.[$k] | .description)"' | grep -w DEPRECATED)"
        echo "$swagger_json" | jq -r '.definitions | keys[] as $k | "\($k): \(.[$k] | .description)"' \
        | grep -i DEPRECATED >> deprecated_apiversion
        major_version="$(echo $version | awk -F '.' '{print $2}')"
        major_version=$(( $major_version+1 ))
        version="1.$(echo $major_version).0"        
    done
}

fetch_deprecated_objects () {
    # this function complies a list of possible deprecated APIs from the given cluster
    deprecated_object_kind="$1"
    total_object_count=""
    if [[ -z "$NAMESPACE" ]];
    then
        deprecated_object_json="$(kubectl get $deprecated_object_kind -A -o json)"
    else
        deprecated_object_json="$(kubectl get $deprecated_object_kind -n $NAMESPACE -o json)"
    fi
    deprecated_apiversion_list="$(echo "$DEPRECATED_LIST" \
    | grep -w "$deprecated_object_kind" | awk -F ':' '{print $2}' | uniq)"
    total_object_count="$(echo "$deprecated_object_json" | jq '.items' | jq length)"

    while read -r line;
    do
        api="$line"
        deprecated_object_list="$(echo "$deprecated_object_json" \
        | jq -rj '.items[] | select(.apiVersion | contains("'$line'")) | .metadata.namespace, ": ",.metadata.name,"\n"')"

        if [[ $? -eq 0 && -z "$deprecated_object_list" ]];
        then
            verbose && \
            echo -e "${RED}$deprecated_object_kind kind objects: ${END}" && \
            echo -e "${GREEN}${TICK} 0 $deprecated_object_kind using deprecated apiVersion: $line${END}" | indent 10 && \
            separator
        else
            echo -e "${RED}$deprecated_object_kind kind objects: ${END}"
            echo -e "${RED}Deprecated $deprecated_object_kind found using deprecated apiVersion: $line${END}" | indent 10
            separator

            # generating csv report for deprecated objects found and their corresponding namespaces
            var="$(paste -d, <(echo "$deprecated_object_kind") <(echo "$line") \
            <(echo -e "$deprecated_object_list" | awk -F ":" '{print $1}') \
            <(echo -e "$deprecated_object_list" | awk -F ": " '{print $2}'))"
            echo "$var" >> "$FILENAME"

            # generate json or plain text for deprecated objects found and their corresponding namespaces
            object_json=""
            deprecated_object_count=0
            while read -r line;
            do
                namespace="$(echo -e "$line" | awk -F ":" '{print $1}')"
                object_name="$(echo -e "$line" | awk -F ": " '{print $2}')"
                object_json="$object_json{ \"namespace\": \"$namespace\", \"object\": \"$object_name\" }, "
                deprecated_object_count=$((deprecated_object_count+1))
            done <<< "$deprecated_object_list"            
            if [[ "$FORMAT" == "json" ]];
            then
                json_object="{ \"kind\": \"$deprecated_object_kind\", \"api\": \"$api\", \"total_deprecated_object_count\": \"$deprecated_object_count\", \"objects\": [ ${object_json%,*} ] }"
                echo "$json_object" | jq . | indent 10
                echo "$json_object" | jq . > "$(date +"%T-%d-%m-%Y").json"
            else
                printf "${BOLD}%-45s%-20s${END}" "NAMESPACE" "$deprecated_object_kind" | indent 10
                echo -e "$deprecated_object_list" | awk -F ": " '{printf("%-45s%-20s\n", $1, $2)}' | indent 10
                separator
            fi
            SUMMARY+=($deprecated_object_kind,$api,$deprecated_object_count,$total_object_count)
        fi
    done <<< "$deprecated_apiversion_list"
}

main () {
    [ "$KUBECONFIG" == "" ] && echo -e "${RED}Please set KUBECONFIG for the cluster.${END}" && exit
    [[ ! -z "$NAMESPACE" ]] && ! kubectl get ns "$NAMESPACE" >/dev/null && exit
    get_swagger
    separator
    echo -e "${RED}Below is the list of deprecated apiVersion which may impact objects in cluster: ${END}"
    separator

    # compiles a list of possible deprecated api and objects in a give k8s version
    DEPRECATED_LIST="$(cat deprecated_apiversion | awk -F ':' '{print $1}' |\
     grep -v DEPRECATED | awk -F '.' '{print $NF":",$(NF-2)"/"$(NF-1)}' | sort | uniq)"
    deprecated_kind="$(echo "$DEPRECATED_LIST" | awk -F ':' '{print $1}' | uniq)"
    printf "${BOLD}%-45s%-10s\n${END}" "K8S_OBJECT" "API_VERSION"
    echo  "$DEPRECATED_LIST" | awk -F": " '{printf("%-45s%-10s\n", $1, $2)}'
    separator

    CURRENT_API_RESOURCES="$(kubectl api-resources --no-headers)"
    checked_object_kind_list=""
    SUMMARY=()
    FREQUENT_OBJECTS=(ClusterRole,ClusterRoleBinding,CustomResourceDefinition,DaemonSet,Deployment,Ingress,NetworkPolicy,PodSecurityPolicy,Role,RoleBinding,StatefulSet)

    FILENAME="$(date +"%T-%d-%m-%Y").csv"
    header=$(paste -d, <(echo "OBJECT_TYPE") <(echo "DEPRECATED_API") <(echo "NAMESPACE") <(echo "OBJECT_NAME"))
    echo "$header" >> "$FILENAME"

    # fetches deprecated objects in running cluster as per the DEPRECATED_LIST
    while read -r line;
    do
        checked_object_kind="$line"
        
        verbose && echo -e "Checking if ${BOLD}$line${END} kind objects exists in the cluster... "
        # local apiversion="$(echo "$DEPRECATED_LIST" | grep "$line" | awk -F ':' '{print $2}' | sort | uniq)"
        if [[ "$CURRENT_API_RESOURCES" == *"$line"* && ! "$checked_object_kind_list" == *"$checked_object_kind"* ]];
        then
            #echo -e "${RED}$line kind objects found${END} in cluster which may be using deprecated apiVersion:"$apiversion""
            if ! verbose;
            then
                printf '%s\n' "${FREQUENT_OBJECTS[@]}" | grep -q -w "$checked_object_kind" \
                && fetch_deprecated_objects "$checked_object_kind"
            else
                fetch_deprecated_objects "$checked_object_kind"
            fi
            checked_object_kind_list="$checked_object_kind_list,$checked_object_kind"
        else
            verbose && echo -e "${GREEN}${TICK} $line: no objects found!${END}" | indent 10 && separator
        fi
    done <<< "$deprecated_kind"
    separator
    printf "${BOLD}Deprecation summary:${END}\n"
    separator
    printf "%-30s%-25s%-20s%-20s\n" "KIND" "API_VERSION" "TOTAL_DEPRECATIONS" | indent 10
    for list in "${SUMMARY[@]}";
    do
        echo -e "$list" | awk -F "," '{printf("%-30s%-25s%-20s\n", $1, $2, $3)}' | indent 10
    done
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
    o)  FORMAT=$OPTARG
        ;;        
    esac
done
shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

[[ -z "$VERSION" ]] && \
echo "[ERROR] Missing mandatory arguments" && usage 
[ -x jq ] && echo -e "${RED}Command 'jq' not found. Please install it.${END}" >&2 && exit 1
main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo "Total time taken:" "$EXECUTION_TIME"s