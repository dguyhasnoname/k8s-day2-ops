#!/bin/bash
##########################################################################
# This script finds errors in namespace pod logs.                        #
# Author: Mukund                                                         #
# Date: 03 April, 2020                                                   #
# Version: 1.0                                                           #
##########################################################################

START_TIME=$(date +%s)
NAMESPACE=${1:-kube-system}
FLAG="$2"
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BOLD='\033[1;30m'
TICK='\xE2\x9C\x94'
NOT_OK='\xE2\x9D\x8C'
END='\033[0m'
GREP_STRING="error\|exception\|timeout|\retry\|unexpected\|denied\|\fail"
VERBOSE_GREP_STRING="warn\|error\|exception\|timeout|\retry\|unexpected\|denied\|IOException|\fail|\unknown"

verbose () {
    [ "$FLAG" == "-v" ] && true
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
    separator
    echo -e "${RED}Usage: ${END}"
    echo "./probe_namespace_errors.sh -h/--h/-help/--help    help"
    echo "./probe_namespace_errors.sh <namespace>            checks for issues with pods in a namespace in last 100 lines of logs"
    echo "./probe_namespace_errors.sh <namespace> <-v>       verbose mode, checks for issues with pods in a namespace in last 500 lines of logs"
    separator
    exit
}

message () {
    OBJECT="$1"
    if  [ "$COUNT" == "0" ];
    then
        echo -e "${GREEN}${TICK}           ${END}"no issues found for "$OBJECT".
    else
        echo -e "\033[1;31;5m[ALERT!]    ${END}"issues found for "$OBJECT"!
    fi
    separator
}

check_namespace() {
    echo "Validating namespace $NAMESPACE ..."
    ns_validation="$(kubectl get ns/"$NAMESPACE")"
    [ "$ns_validation" != "" ] && echo -en "\033[0;32mNamespace $NAMESPACE found.${END}" && echo " Fetching pods in namespace $NAMESPACE..."
    [ "$ns_validation" == "" ] && echo -e "${RED}[ERROR]${END}" Namespace "$NAMESPACE" was not found! Please provide correct namespace. && exit
}

pod_list_namespace () {
    POD_JSON_NAMESPACE="$(kubectl get pods -o json -n  "$NAMESPACE")"
    pod_list="$(echo "$POD_JSON_NAMESPACE" | jq -r '.items[].metadata.name')"
}

check_pod_logs_previous () {
    pod_container_list="$(echo "$POD_JSON_NAMESPACE" | jq  -r '.items[] | select (.metadata.name == "'$line'") | .spec.containers[].name')"
    while read -r line;
    do
        previous_log="$(kubectl logs "$current_pod" -c "$line" -n "$NAMESPACE" --tail=500 |  grep -i ${VERBOSE_GREP_STRING} | tail -3)"
        echo "$previous_log"
    done <<< "$pod_container_list"
}

check_pod_logs () {
    pod_list_namespace
    while read -r line;
    do
        if verbose;
        then
            pod_log="$(kubectl logs "$line" -n "$NAMESPACE" --all-containers --tail=500 |  grep -i  ${VERBOSE_GREP_STRING} | tail -3)"
        else
            pod_log="$(kubectl logs "$line" -n "$NAMESPACE" --all-containers  --tail=100|  grep -i  ${GREP_STRING} | tail -3)"
        fi
        if [ "$pod_log" != "" ];
        then
            separator
            echo -e "${RED} ${NOT_OK}[ISSUE] Pod:${END} $line."
            echo -e "${BOLD}Issues found in logs of pod $line:${END}" | indent 16
            echo -e "\033[0;31m$pod_log${END}" | fold -w 110 -s| indent 16
        else
            current_pod="$line"
            verbose && check_pod_logs_previous
            echo -e "${GREEN} ${TICK}[OK]     Pod:${END} $current_pod."
        fi
    done <<< "$pod_list"
}

probe () {
    [ "$KUBECONFIG" == "" ] && echo "Please set KUBECONFIG for the cluster." && exit
    [ -x jq ] && echo "Command 'jq' not found. Please install it." >&2 && exit 1
    check_namespace
    clear
    echo "-------------------------------------------------------------"
    echo -e "\033[0;32mChecking pod logs in namespace $NAMESPACE:${END}"
    echo "-------------------------------------------------------------"
    check_pod_logs
}

main () {
    [[ "$NAMESPACE" == "-h" || "$NAMESPACE" == "--h" || "$NAMESPACE" == "-help" || "$NAMESPACE" == "--help" ]] && usage
    if [[ "$NAMESPACE" == "-v" ]];
    then
        NAMESPACE="kube-system"
        FLAG="-v"
        probe
    else
        probe
    fi
    separator
    END_TIME=$(date +%s)
    EXECUTION_TIME=$((END_TIME-START_TIME))
    echo "Total time taken:" "$EXECUTION_TIME"s
}

main