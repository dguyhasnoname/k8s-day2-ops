#!/bin/bash -e
#######################################################################
# This script greps for case-insentitive 'error' string in a pod over #
# the last 5 minutes. It can optionally add additional param like     #
# '10m' or '24h' to change the --TIME= value. Default ns is kube-     #
# system. This script needs KUBECONFIG to be exported prior to run it.#
# Author: Mukund                                                      #
# Date: 17th August 2019                                              #
# Version: 1.0                                                        #
#######################################################################

POD_NAME="$1"
TIME="${2:-5m}"
NAMESPACE="${3:-kube-system}"
STRING="$4"

usage() {
    echo "[WARNINIG]: It may be a invalid sytanx!"
    echo "Usage: pod_error_count.sh <pod_names_to_grep> <optional time(5m or 2h); default 5m> <namespace, default vaules is kube-system>  <optional search string>."
    echo "e.g pod_error_count.sh  kube-proxy 24h kube-system invalid"
    separator
    exit
}

separator() {
    echo "------------------------------------------------------------------------------------------------------------------"
}

pod_list(){
    separator
    POD_LIST="$(kubectl -n "$NAMESPACE" get pods --no-headers | grep -i "$POD_NAME" |  awk '{print $1}')"

    if [[ "$POD_LIST" == "" ]];
    then
        echo "[WARNINIG]: Pod $POD_NAME not found in namespace $NAMESPACE"
        usage
        separator
        exit
    else
        true
    fi
}

get_count() {
    [ -z "$POD_NAME" ] && usage
    pod_list
    printf "fetching error count in namespace for below pods in last $TIME...\n\n"
    while IFS= read -r line;
    do
        ERROR_COUNT=$(kubectl -n "$NAMESPACE" logs "$line" --since="$TIME" | grep -aci error)
        echo "Pod = $line, Error count = $ERROR_COUNT"
    done <<< "$POD_LIST"
    separator
}

grep_error() {
    [ -z "$STRING" ] && get_count && exit
    printf "searching for string $STRING in logs for below pods in namespace $NAMESPACE in last $TIME...\n\n"
    pod_list
    while IFS= read -r line;
    do
        ERROR_COUNT=$(kubectl -n "$NAMESPACE" logs "$line" --since="$TIME" | grep -aci "$STRING")
        echo "Pod = $line, Error count for errors related to string $STRING = $ERROR_COUNT"
    done <<< "$POD_LIST"
    separator
}

grep_error