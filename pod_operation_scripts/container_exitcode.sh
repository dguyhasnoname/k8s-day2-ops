#!/bin/bash -e
#######################################################################
# This script gives the detail of containers which got restarted due  #
# to multiple reasons like OOM with exit code, restart  count, start/ #
# end date and node name. KUBECONFIG needs to be exported before run- #
# ning this script.                                                   #
# Author: Mukund                                                      #
# Date: 16th August 2019                                              #
# Version: 1.0                                                        #
#######################################################################
clear

NAMESPACE=$1

separator() {
    echo "------------------------------------------------------------------------------------------------------------------------------------------"
}

[[ "$1" == "-h" ]] && echo "Usage: ./container_exitcode.sh <namespace>" && exit

gen_report() {
    echo "Fetching details..."
    PODS="$(kubectl get pods -n "$NAMESPACE" --no-headers)"

    [ ! -n "$PODS" ] && echo Please check the namespace provided.  && exit
    separator
    printf "%-30s %-45s %-5s %-10s %-22s %-22s\n" CONTAINER_NAME/RESTART_COUNT NODE_NAME CODE REASON START_TIME END_TIME
    separator

    FLAG=0
    while read -r line;
    do
        RESTART_COUNT=$(echo "$line" | awk  '{print $4}')
        if [[ $RESTART_COUNT -gt 0 ]];
        then
            line=$(echo "$line" | awk '{print  $1}')
            OUTPUT=$(kubectl get pod "$line" -n "$NAMESPACE" -o json | jq -j '.status.containerStatuses[].name, " ", 
            .status.containerStatuses[].restartCount, " ", .spec.nodeName, " ",
             .status.containerStatuses[].lastState.terminated.exitCode, " ",
             .status.containerStatuses[].lastState.terminated.reason, " ",
             .status.containerStatuses[].lastState.terminated.startedAt, " ",
             .status.containerStatuses[].lastState.terminated.finishedAt, " ",
             .metadata.name, " ", .status.phase, "\n"|  select(. != null)')
            ! echo OUTPUT | grep -qi completed && echo "$OUTPUT" | awk '{ printf "%-30s %-45s %-5s %-10s %-22s %-22s\n", $1"/"$2, $3, $4, $5, $6, $7 }'
            FLAG=$((FLAG+1))
        fi
    done < <(printf '%s\n' "$PODS")

    [ "$FLAG" -eq 0 ] && echo "No pods found with restarted containers!"
    separator
}

[ -n "$1" ] && gen_report || echo ["ERROR]: Missing namespace. Usage: ./container_exitcode.sh kube-system"