#!/bin/bash
########################################################################
# This script deletes multiple objects which contains given match in a #
# namespace. KUBECONFIG needs to be exported prior running the script  #
# Author: Mukund                                                       #
# Date: 8th June 2020                                                  #
# Version: 2.0                                                         #
########################################################################

START_TIME=$(date +%s)
NAMESPACE=""
QUICK_DELETE=""

usage() {
    separator
    echo "Usage: "
    echo "****Export KUBECONFIG before running the script.***"
    separator
    echo "Examples:"
    echo "./multiple_object_delete.sh -n <namespace> -o <object> -s <string>     deletes multiple objects which contains given string one at a time."
    echo "./multiple_object_delete.sh -n <namespace> -o <object> -s <string> -q  deletes multiple pods which contains given string in parallel mode."
    echo "./multiple_object_delete.sh -n kube-system -o pod -s kube-proxy"
    separator
    echo "Options:"
    echo "-n <namespace>       namespace name"
    echo "-o <object>          object type"
    echo "-s <string>          string"
    echo "-q                   quick mode"
    separator 
    echo "./multiple_object_delete.sh -h/-help/--h                               help"
    separator
    exit
}

separator() {
    echo ""
}

get_objects() {
    separator
    printf '%s\n' "Checking for pod containing string $STRING in namespace $NAMESPACE:"
    separator
    LIST_OBJECTS="$(kubectl get $OBJECT --no-headers -n "$NAMESPACE"| grep -i "$STRING" | awk '{print $1}')"
    if [[ "$LIST_OBJECTS" == "" ]];
    then
        printf '\e[1;31m%s\e[0m\n\n' "Either namespace $NAMESPACE doesn't exists OR $OBJECT with name containing string '$STRING' was not found in namespace $NAMESPACE."
        exit
    else
        printf '\e[1;32m%s\e[0m\n\n' "Below $OBJECT were found in namespace $NAMESPACE with containing string $STRING: "
        echo "$LIST_OBJECTS"
    fi
}

delete_objects () {   
    get_objects
    printf '\e[1;33m%s\e[0m' "Do you want to delete the pods(Y/N):  "
    read -r  USER_INPUT
    separator
    if [[ "$USER_INPUT" == "Y" ]];
    then
        if [[ -z "$QUICK_DELETE" ]];
        then
            echo "****Deleting $OBJECT one by one.****"
            separator
            while read -r line;
            do
                kubectl delete $OBJECT "$line" -n "$NAMESPACE"
            done <<< "$LIST_OBJECTS"
        else
            echo "****Deleting $OBJECT in parallel mode!****"
            separator
            parallel --jobs=10 "echo {}; kubectl delete ${OBJECT} {} -n ${NAMESPACE};" ::: ${LIST_OBJECTS}
        fi

        separator
        printf '\e[1;32m%s\e[0m\n\n' "Checking $OBJECT status after deletion: "
        kubectl get $OBJECT --no-headers -n "$NAMESPACE" | grep -i "$STRING"
    else
        echo "Did not get input to delete pods. No actions taken!"
        echo "Exiting script!"
    fi
    separator
}


OPTIND=1         

while getopts "h?n:qs:o:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    n)  NAMESPACE=$OPTARG
        ;;
    q)  QUICK_DELETE=true
        ;;     
    s)  STRING=$OPTARG 
        ;;
    o)  OBJECT=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

[[ -z "$NAMESPACE"  || -z "$OBJECT" || -z "$STRING" ]] && \
echo "[ERROR] Missing mandatory arguments" && usage 
[ -x parallel ] && echo -e "${RED}Command 'parallel' not found. Please install it.${END}" >&2 && exit 1
delete_objects

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
echo "Total time taken:" "$EXECUTION_TIME"s