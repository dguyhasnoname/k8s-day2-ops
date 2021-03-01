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
    echo "  -v   Mandatory      Kubernetes version to be checked. Gets all deprecations in k8s api."
    echo "  -d   Optional       Debug mode, all deprecations in k8s api alongwith objects using it."
    echo "  -n   Optional       Pass namespace name to get namespaced deprecations in k8s api alongwith objects using it."
    echo "  -o   Optional       Output in json/csv format. Valid values are json & csv."
    separator
    exit
}

# this function complies a list of possible deprecated APIs from k8s repo
get_swagger () {
    separator
    echo "Gathering info of current cluster..."

    current_k8s_version="$(kubectl get nodes -o json \
    | jq -r '.items[].status.nodeInfo.kubeletVersion' | uniq | sed 's/\v//g')"

    echo "Current k8s version: v$current_k8s_version"
    version="$(echo $current_k8s_version | sed 's/\(.*\)\..*/\1/').0"
    UPGRADE_PATH="v$current_k8s_version"
    while [[ "$(echo "$version "| awk -F '.' '{print $2}')" -le "$(echo "$VERSION" | awk -F '.' '{print $2}')" ]];
    do
        echo "Fetching all objects from kubenetes repo: v$version..."
        swagger_json="$(curl -s swagger-v"$version".json \
        https://raw.githubusercontent.com/kubernetes/kubernetes/v"$version"/api/openapi-spec/swagger.json)"

        deprecated_apiversion_description="$(echo "$swagger_json" | jq -r '.definitions 
        | keys[] as $k | "\($k): \(.[$k] | .description)"' \
        | grep -i DEPRECATED | awk -F ":" '{print $1}')"

        echo "$swagger_json" | jq -r '.definitions | keys[] as $k 
        | "\($k): \(.[$k] | select(."x-kubernetes-group-version-kind" != null) 
        | ."x-kubernetes-group-version-kind"[].group)/\(.[$k] 
        | select(."x-kubernetes-group-version-kind" != null) 
        | ."x-kubernetes-group-version-kind"[].version)"' >> deprecated_apiversion_group_version_kind 
        
        while read -r line;
        do
            deprecated_api="$(cat deprecated_apiversion_group_version_kind \
            | grep "$line" | awk -F ": " '{print $2}' | uniq)"
            kind="$(echo $line | awk -F '.' '{print $NF}')"
            [[ ! -z "$deprecated_api" ]] && echo "$kind: $deprecated_api" >> deprecated_apiversion
        done <<< "$deprecated_apiversion_description"
        major_version="$(echo $version | awk -F '.' '{print $2}')"
        major_version=$(( $major_version+1 ))
        version="1.$(echo $major_version).0"        
    done
    separator
    echo -e "${RED}Below is the list of deprecated apiVersion which may impact objects in cluster: ${END}"
    separator    
    deprecated_kind="$(awk -F ': ' '{print $1}' deprecated_apiversion \
    | grep -vw 'Binding' | awk '!a[$0]++' | sort)"

    printf "${BOLD}%-45s%-10s\n${END}" "K8S_OBJECT" "API_VERSION"
    awk -F ": " '{printf("%-45s%-10s\n", $1, $2)}' deprecated_apiversion \
    | awk '!a[$0]++' | sort && separator
    DEPRECATED_LIST="$(awk '!a[$0]++' deprecated_apiversion | grep -vw 'Binding' | sort)"
}

# this function complies a list of possible deprecated APIs from the given cluster
fetch_deprecated_objects () {
    deprecated_object_kind="$1"
    total_object_count=""
    
    if [[ -z "$NAMESPACE" ]];
    then
        deprecated_object_json="$(kubectl get $deprecated_object_kind -A -o json)"
    else
        deprecated_object_json="$(kubectl get $deprecated_object_kind -n $NAMESPACE -o json)"
    fi
    
    deprecated_apiversion_list="$(echo "$DEPRECATED_LIST" \
    | grep -w "$deprecated_object_kind" | awk -F ': ' '{print $2}' | uniq)"
    total_object_count="$(echo "$deprecated_object_json" | jq '.items' | jq length)"

    while read -r line;
    do
        api="$line"
        deprecated_object_list="$(echo "$deprecated_object_json" \
        | jq -rj '.items[] | select(.apiVersion | contains("'$line'")) 
        | .metadata.namespace, ": ",.metadata.name,"\n"')"

        if [[ $? -eq 0 && -z "$deprecated_object_list" ]];
        then
            verbose && \
            echo -e "${RED}$deprecated_object_kind kind objects: ${END}" && \
            echo -e "${GREEN}${TICK} 0 $deprecated_object_kind using deprecated apiVersion: $line${END}" | indent 10 && \
            separator
        else
            [[ "$FORMAT"  != "csv" ]] && \
            echo -e "${RED}$deprecated_object_kind kind objects: ${END}" && \
            echo -e "${RED}Deprecated $deprecated_object_kind found using deprecated apiVersion: $line${END}" | indent 10 && \
            separator

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
            
            # print output in plain text/json/csv         
            if [[ "$FORMAT" == "json" ]];
            then
                json_object="{ \"kind\": \"$deprecated_object_kind\",
                               \"api\": \"$api\",
                               \"total_deprecated_object_count\": \"$deprecated_object_count\", 
                               \"objects\": [ ${object_json%,*} ] 
                             }"
                echo "$json_object" | jq . | indent 10
                separator
                echo "$json_object" | jq . >> "$FILENAME.json"
            elif [[ "$FORMAT" == "csv" ]];
            then
                # generating csv report for deprecated objects found and their corresponding namespaces
                
                if [ ${#SUMMARY[@]} -eq 0 ];
                then
                    header=$(paste -d, <(echo "OBJECT_TYPE") <(echo "DEPRECATED_API") <(echo "NAMESPACE") <(echo "OBJECT_NAME"))
                    echo "$header" >> "$FILENAME.csv"
                fi
                var="$(paste -d, <(echo "$deprecated_object_kind") <(echo "$api") \
                <(echo -e "$deprecated_object_list" | awk -F ": " '{print $1}' | sed "s/null/GLOBAL/" ) \
                <(echo -e "$deprecated_object_list" | awk -F ": " '{print $2}'))"
                echo "$var" >> "$FILENAME.csv"
            else
                printf "${BOLD}%-45s%-20s${END}" "NAMESPACE" "$deprecated_object_kind" | indent 10
                echo -e "$deprecated_object_list" | awk -F ": " '{printf("%-45s%-20s\n", $1, $2)}' \
                | sed "s/null/GLOBAL/" | indent 10
                separator
            fi
            SUMMARY+=($deprecated_object_kind,$api,$deprecated_object_count,$total_object_count)
             
        fi
    done <<< "$deprecated_apiversion_list"
}

main () {
    [ "$KUBECONFIG" == "" ] && usage
    [[ ! -z "$NAMESPACE" ]] && ! kubectl get ns "$NAMESPACE" >/dev/null && exit
    
    get_swagger
    CURRENT_API_RESOURCES="$(kubectl api-resources --no-headers)"
    checked_object_kind_list=""
    SUMMARY=()
    FREQUENT_OBJECTS=(ClusterRole,ClusterRoleBinding,CustomResourceDefinition,DaemonSet,Deployment,Ingress,NetworkPolicy,PodSecurityPolicy,Role,RoleBinding,StatefulSet)
    FILENAME="$(date +"%T-%d-%m-%Y")"

    # fetches deprecated objects in running cluster as per the DEPRECATED_LIST
    while read -r line;
    do
        checked_object_kind="$line"
        echo -e "Checking if ${BOLD}$line${END} kind objects exists in the cluster... "

        if [[ "$CURRENT_API_RESOURCES" == *"$line"* && ! "$checked_object_kind_list" == *"$checked_object_kind"* ]];
        then
            fetch_deprecated_objects "$checked_object_kind"
            checked_object_kind_list="$checked_object_kind_list,$checked_object_kind"
        else
            verbose && echo -e "${GREEN}${TICK} $line: no objects found!${END}" | indent 10 && separator
        fi
    done <<< "$deprecated_kind"

    [[ "$FORMAT" == "json" ]] && echo -e "${BOLD}JSON file generated:${END} $FILENAME.json"
    [[ "$FORMAT" == "csv" ]] && echo -e "${BOLD}Report generated.${END} Please check the report in file $FILENAME.csv"
    printf "\n${BOLD}Deprecation summary:${END}\n\n"
    printf "%-40s%-40s%-20s\n" "KIND" "API_VERSION" "TOTAL_DEPRECATIONS" | indent 10

    for list in "${SUMMARY[@]}";
    do
        echo -e "$list" | awk -F "," '{printf("%-40s%-40s%-20s\n", $1, $2, $3)}' | indent 10
    done
    rm deprecated_apiversion deprecated_apiversion_group_version_kind
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

[[ -z "$VERSION" ]] && echo "[ERROR] Missing mandatory arguments" && usage 
[ -x jq ] && echo -e "${RED}Command 'jq' not found. Please install it.${END}" >&2 && exit 1

main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo "Total time taken:" "$EXECUTION_TIME"s