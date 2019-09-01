#!/bin/bash
##########################################################################
# This script finds all possible issues in namespace.                    #
# Author: Mukund                                                         #
# Date: 29th August 2019                                                 #
# Version: 1.0                                                           #
##########################################################################

START_TIME=$(date +%s)
NAMESPACE=${1:-kube-system}
FLAG="$2"

verbose () {
    [ "$FLAG" == "-v" ] && true
}

separator() {
    printf '\n'
}

usage() {
    echo "[WARNING]: Export KUBECONFIG before running the script."
    echo "Usage: "
    echo "./debug_app_namespace.sh -h/-help/--h           help"
    echo "./debug_app_namespace.sh <namespace>            checks for issues with k8s objects in a namespace"
    echo "./debug_app_namespace.sh <namespace> <-v>       debug mode, prints objects with no issues too"
    exit
}

check_namespace() {
    echo "Validating namespace $NAMESPACE ..."
    kubectl get ns/"$NAMESPACE" && echo -en "\033[0;32mNamespace $NAMESPACE found.\033[0m" && echo " Fetching objects in namespace $NAMESPACE..."
    [ ! $? -eq 0 ] && echo -e "\033[1;31m[ERROR]\033[0m" Namespace "$NAMESPACE" was not found! Please provide correct namespace. && exit
}

pvc_check () {
    if [[ "$PVC_STATUS" != "Bound" ]];
    then
        echo -e "\033[1;33m! [WARNING] pvc\033[0m" "$line"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      \033[0m" "$line"
    fi

    [ "$COUNT" == "0" ] && echo -e "\033[1;32m\xE2\x9C\x94            \033[0m"no issues found for pvc "$PVC_NAME". \
    || echo -e "\033[1;31m[ALERT!]    \033[0m"issues found for pvc "$PVC_NAME".
}

pv_check () {
    if [[ "$PV_STATUS" != "Bound" ]];
    then
        echo -e "\033[1;33m! [WARNING] pv\033[0m" "$line"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]    pv\033[0m" "$line"
    fi
}

csp_check () {
    STATUS="$(echo "$line" | awk '{print $5}')"
    OUTPUT="$(echo "$line" | awk '{printf "%-10s %-5s %-5s %-5s %-10s %-10s %-10s\n", $1, $2, $3, $4, $5, $6, $7}')"
    if [[ "$STATUS" != "Healthy" ]];
    then
        echo -e "\033[1;33m! [WARNING] CStorPool\033[0m" "$OUTPUT"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorPool\033[0m" "$OUTPUT"
    fi
}

cstorvolume_check () {
    OUTPUT="$(echo "$line" | awk '{printf "%-40s %-10s %-8s\n", $2, $3, $4}')"
    if [[ "$CV_STATUS" != "Healthy" ]];
    then
        [[ "$CV_STATUS" == "Offline" ]] && echo -e "\033[1;33m! [WARNING] CStorVolume\033[0m" "$OUTPUT" \
        || echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   CStorVolume\033[0m" "$OUTPUT"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorVolume\033[0m" "$OUTPUT"
    fi
}

cvr_check () {
    OUTPUT="$(echo "$line" | awk '{printf "%-40s %-5s %-5s %-10s %-5s\n", $2, $3, $4, $5, $6}')"
    if [[ "$CVR_STATUS" != "Healthy" ]];
    then
        [[ "$CVR_STATUS" == "Offline" ]] && echo -e "\033[1;33m! [WARNING] CStorVolumeReplica\033[0m" "$OUTPUT" \
        || echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   CStorVolumeReplica\033[0m" "$OUTPUT"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorVolumeReplica\033[0m" "$OUTPUT"
    fi
}

peristent_storage () {
    COUNT=0
    PVC_LIST="$(kubectl get pvc -n "$NAMESPACE"  --no-headers 2> /dev/null)"
    #loop  over pvc
    if [[ "$PVC_LIST" == "" ]];then
        echo -e "\033[0;33mPersistent storage not configured\033[0m for namespace $NAMESPACE."
        return
    fi
    while read -r line;
    do
        separator
        PVC_STATUS="$(echo "$line" | awk '{print $2}')"
        PVC_NAME="$(echo "$line" | awk '{print $1}')"
        echo -e "\033[0;32mPVC details for pvc $PVC_NAME:\033[0m"
        separator
        pvc_check

        NAMESPACE_PV_LIST="$(kubectl get pv --no-headers | grep "$PVC_NAME")"
        separator
        #looping over pv
        while read -r line;
        do
            PV_NAME="$(echo "$line" | awk '{print $1}')"
            PV_STATUS="$(kubectl get pv -A --no-headers| grep "$PV_NAME" | awk '{print $5}')"
            echo -e "\033[0;32mPV details for pv $PV_NAME:\033[0m" | sed 's/^/      /'
            COUNT=0
            pv_check | sed "s/^/      /"

            [ "$COUNT" == "0" ] && echo -e "\033[1;32m\xE2\x9C\x94            \033[0m"no issues found for pv "$PV_NAME". | sed "s/^/      /" \
            || echo -e "\033[1;31m[ALERT!]    \033[0m"issues found for pv "$PV_NAME". | sed "s/^/      /"

            NS_CV_LIST="$(kubectl get cstorvolumes -A --no-headers | grep "$PV_NAME")"
            if [ "$NS_CV_LIST" != "" ];
            then
                separator
                echo -e "\033[0;32mCStorVolume details for pv $PV_NAME:\033[0m" | sed "s/^/            /"
                COUNT=0
                while read -r line;
                do
                    NS_CV_STATUS="$(echo "$line" | awk '{print$3}')"
                    CV_STATUS=$NS_CV_STATUS
                    cstorvolume_check | sed "s/^/            /"
                done <<< "$NS_CV_LIST"

                [ "$COUNT" == "0" ] && echo -e "\033[1;32m\xE2\x9C\x94           \033[0m"no issues found with any of CStorVolume. | sed "s/^/            /" \
                || echo -e "\033[1;31m[ALERT!]    \033[0m"issues found for CStorVolume! | sed "s/^/            /"
            fi

            NS_CVR_LIST="$(kubectl get cvr -A --no-headers | grep "$PV_NAME")"
            if [ "$NS_CVR_LIST" != "" ];
            then
                separator
                echo -e "\033[0;32mCStorVolumeReplica details for pv $PV_NAME:\033[0m" | sed "s/^/            /"
                COUNT=0
                while read -r line;
                do
                    NS_CVR_STATUS="$(echo "$line" | awk '{print $5}')"
                    CVR_STATUS=$NS_CVR_STATUS
                    cvr_check | sed "s/^/            /"
                done <<< "$NS_CVR_LIST"

                [ "$COUNT" == "0" ] && echo -e "\033[1;32m\xE2\x9C\x94           \033[0m"no issues found with any of CStorVolumeReplica. | sed "s/^/            /" \
                || echo -e "\033[1;31m[ALERT!]    \033[0m"issues found for CStorVolumeReplica! | sed "s/^/            /"
            fi
        done <<< "$NAMESPACE_PV_LIST"
    done <<< "$PVC_LIST"
}

pod_container_restart () {
    POD_JSON="$(kubectl get pods "$POD_NAME" -o json -n  "$NAMESPACE")"
    RESTARTED_CONTAINER_LIST="$(echo "$POD_JSON" | jq -r  '.status.containerStatuses[].name')"
    while read -r line;
    do
        CONTAINER_JSON="$(echo "$POD_JSON" | jq  -rj '.status.containerStatuses[] | select (.name == "'$line'") | .lastState.terminated |  select(. != null) | .reason, " ", .exitCode, " ", .startedAt, " ", .finishedAt, "\n"')"
        if [[ "$CONTAINER_JSON" != "" && $(echo "$CONTAINER_JSON" | awk '{print $1}') != "Completed" ]];
        then
            echo -e "Container \033[1;33m$line\033[0m restart count: $RESTART" | sed "s/^/                /"
            echo "$CONTAINER_JSON" | awk '{printf "\033[1;31m%-10s\033[0m %-5s %-25s %-25s\n", $1, $2, $3, $4}' | sed "s/^/                /"
        else
            echo -e "Container \033[1;33m$line\033[0m restart count: $RESTART" | sed "s/^/                /"
            echo -e "Container $line was last terminated with exitCode: \033[0;32m0\033[0m and reason: \033[0;32mCompleted\033[0m " | sed "s/^/                /"  
        fi
    done <<< "$RESTARTED_CONTAINER_LIST"
    separator
}

pod_state_crashloopbackoff () {
    POD_STATE_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status.containerStatuses')"
    POD_STATE_CONTAINER_LIST="$(echo "$POD_STATE_JSON" | jq -r  '.[].name')"
    while read -r line;
    do
        POD_STATE_CONTAINER_JSON="$(echo "$POD_STATE_JSON" | jq  -r '.[] | select (.name == "'$line'") | .state')"
        echo -e "Reason of failure:" | sed "s/^/                /"
        echo -e "\033[0;33m$POD_STATE_CONTAINER_JSON\033[0m" | sed "s/^/                /"
        pod_container_restart
    done <<< "$POD_STATE_CONTAINER_LIST"
}

pod_state_evicted () {
    POD_STATE_EVICT_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status')"
    echo -e "Reason of eviction:" | sed "s/^/                /"
    echo -e "\033[0;31m$POD_STATE_EVICT_JSON\033[0m" | sed "s/^/                /"
}

pods () {
    COUNT=0
    echo -e "\033[0;32mPod details:\033[0m"
    separator
    POD_LIST="$(kubectl get pods -o wide --no-headers -n "$NAMESPACE" 2> /dev/null)"
    if [[ "$POD_LIST" == "" ]];then
        echo -e "\033[1;33m! [WARNING]    \033[0m 0 pods running in namespace $NAMESPACE."
        return
    else
        POD_COUNT="$(echo "$POD_LIST" | wc -l)"
        echo -e "\033[1;32m\xE2\x9C\x94           pods found:$POD_COUNT\033[0m"
    fi
    while read -r line;
    do
        STATUS="$(echo "$line" | awk '{print $3}')"
        POD_NAME="$(echo "$line" | awk '{print $1}')"
        POD_AGE="$(echo "$line" | awk '{print $5}')"
        POD_NODE="$(echo "$line" | awk '{print $7}')"
        RESTART="$(echo "$line" | awk '{print $4}')"

        if [[ "$STATUS" == "CrashLoopBackOff" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_crashloopbackoff
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "Evicted" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_evicted
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "Completed" ]];
        then
            verbose && echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
        fi
        if [[ "$STATUS" == "CreateContainerConfigError" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_crashloopbackoff
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "Running" ]];
        then
            CONTAINERS_RUNNING="$(echo "$line" | awk '{print $2}')"
            if [[ "$(echo "$CONTAINERS_RUNNING" | awk -F '/' '{print $1}')" ==  "$(echo "$CONTAINERS_RUNNING" | awk -F '/' '{print $2}')" ]];
            then
                verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pod\033[0m" "$POD_NAME" "$POD_NODE"
            #else
                if [[ "$RESTART" -gt 0 ]];
                then
                    echo -e "\033[1;33m! [WARNING] pod\033[0m" "$POD_NODE"/"$POD_NAME" is "\033[1;32mRunning\033[0m" since "$POD_AGE", having containers restarted.
                    COUNT=$((COUNT+1))
                    pod_container_restart
                else
                    verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pod\033[0m" "$POD_NAME" "$POD_NODE"
                fi
            fi
        fi
    done <<< "$POD_LIST"
    [ "$COUNT" == "0" ] && echo -e "\033[1;32m\xE2\x9C\x94           \033[0m"no issues found with any of pods. \
    || echo -e "\033[1;31m[ALERT!]    \033[0m"issues found for pods!
}

rs () {
    COUNT=0
    echo -e "\033[0;32mReplicaSet details:\033[0m"
    separator
    RS_LIST="$(kubectl get rs -n $NAMESPACE --no-headers | awk '{if($2!=0) print}' 2> /dev/null)"
    if [[ "$RS_LIST" == "" ]];
    then
        echo -e "\033[1;33m! [WARNING]    \033[0m 0 replicasets running in namespace $NAMESPACE."
        return
    else
        RS_COUNT="$(echo "$RS_LIST" | wc -l)"
        echo -e "\033[1;32m\xE2\x9C\x94           replicaset found:$RS_COUNT\033[0m"
    fi
    while read -r line;
    do
        if [[ "$(echo "$line" | awk '{print $2}')" != "$(echo "$line" | awk '{print $4}')" ]];
        then
            echo -e "\033[1;33m! [WARNING] replicaset\033[0m" "$line"
            COUNT=$((COUNT+1))
        else
            verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      replicaset\033[0m" "$line"
        fi
    done <<< "$RS_LIST"
    [ "$COUNT" == "0" ] && echo -e "\033[1;32m\xE2\x9C\x94           \033[0m"no issues found with any of replicasets. \
    || echo -e "\033[1;31m[ALERT!]    \033[0m"issues found for replicasets!
    separator
}
debug_ns() {
    [ "$KUBECONFIG" == "" ] && echo "Please set KUBECONFIG for the cluster." && exit
    check_namespace
    clear
    echo "-------------------------------------------------------------"
    echo -e "\033[0;32mCrawling objects in namespace $NAMESPACE:\033[0m"
    echo "-------------------------------------------------------------"
    rs
    pods
    peristent_storage
    separator
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
debug_ns

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
echo Total time taken: "$EXECUTION_TIME"s