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

message () {
    OBJECT="$1"
    if  [ "$COUNT" == "0" ];
    then
        echo -e "\033[1;32m\xE2\x9C\x94           \033[0m"no issues found for $OBJECT.
    else
        echo -e "\033[1;31;5m[ALERT!]    \033[0m"issues found for $OBJECT!
    fi
}

check_namespace() {
    echo "Validating namespace $NAMESPACE ..."
    NS_VALIDATION="$(kubectl get ns/"$NAMESPACE")"
    [ "$NS_VALIDATION" != "" ] && echo -en "\033[0;32mNamespace $NAMESPACE found.\033[0m" && echo " Fetching objects in namespace $NAMESPACE..."
    [ "$NS_VALIDATION" == "" ] && echo -e "\033[1;31m[ERROR]\033[0m" Namespace "$NAMESPACE" was not found! Please provide correct namespace. && exit
}

pvc_check () {
    if [[ "$PVC_STATUS" != "Bound" ]];
    then
        echo -e "\033[1;33m! [WARNING] pvc\033[0m" "$line"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pvc\033[0m" "$PVC_NAME"
    fi
    message pvc
}

pv_check () {
    if [[ "$PV_STATUS" != "Bound" ]];
    then
        echo -e "\033[1;33m! [WARNING] pv\033[0m" "$line"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pv\033[0m" "$line"
    fi
    message pv
}

csp_check () {
    csp_stats () {
        kubectl get csp -o json | jq -r '.items[] | select(.metadata.name | contains("'$CSP_NAME'")) | .metadata.labels."kubernetes.io\/hostname", .status.capacity' | sed 's/^/            /'
    }
    CSP_LIST="$(kubectl get csp -o json | jq -r '.items[].metadata.name')"
    if [[ "$CSP_LIST" != "" ]];
    then
        echo -e "\033[0;32mcStor configuration found for namespace $NAMESPACE..\033[0m"
        while read -r line;
        do
            CSP_NAME="$line"
            CSP_STATUS="$(kubectl get csp -o json | jq -r '.items[] | select(.metadata.name | contains("'$CSP_NAME'")) | .status.phase')"
            if [[ "$CSP_STATUS" != "Healthy" ]];
            then
                verbose && echo -e "\033[1;33m! [WARNING] CStorPool\033[0m" "$CSP_NAME $CSP_STATUS" && csp_stats
                COUNT=$((COUNT+1))
            else
                verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorPool\033[0m" "$CSP_NAME $CSP_STATUS" && csp_stats
            fi
        done <<< "$CSP_LIST"
        message cStorPool
    fi
}

cstorvolume_check () {
    replica_check () {
        kubectl get cstorvolumes -A -o json | jq -r '.items[] | select(.metadata.name | contains("'$PV_NAME'")) | "Specs:", .spec, "Replica status:", .status.replicaStatuses[]' | sed 's/^/            /'
    }
    CV_STATUS="$(kubectl get cstorvolumes -A -o json | jq -r '.items[] | select(.metadata.name | contains("'$PV_NAME'")) | .status.phase' )"
    if [[ "$CV_STATUS" != "Healthy" ]];
    then
        verbose && echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]    CStorVolume\033[0m" "$CV_NAME" "$CV_STATUS" && replica_check
        COUNT=$((COUNT+1))
    elif [[ "$CV_STATUS" == "Offline" ]];
    then
        verbose && echo -e "\033[1;33m! [WARNING]  CStorVolume\033[0m" "$CV_NAME" "$CV_STATUS" && replica_check
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorVolume\033[0m" "$CV_NAME" "$CV_STATUS" && replica_check
    fi
}

cvr_check () {
    cvr_status_detail () {
        kubectl get cvr -A -o json | jq -r '.items[] | select(.metadata.name | contains("'$CVR_NAME'")) | .status' | sed 's/^/            /'
    }
    CVR_STATUS="$(kubectl get cvr -A -o json | jq -r '.items[] | select(.metadata.name | contains("'$CVR_NAME'")) | .status.phase')"
    if [[ "$CVR_STATUS" != "Healthy" ]];
    then
        verbose && echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]    CStorVolumeReplica\033[0m" "$CVR_NAME" "$CVR_STATUS" && cvr_status_detail
        COUNT=$((COUNT+1))
    elif [[ "$CVR_STATUS" == "Offline" ]];
    then
        verbose && echo -e "\033[1;33m! [WARNING] CStorVolumeReplica\033[0m" "$CVR_NAME" "$CVR_STATUS" && cvr_status_detail
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorVolumeReplica\033[0m" "$CVR_NAME" "$CVR_STATUS" && cvr_status_detail
    fi
}

peristent_storage () {
    separator
    COUNT=0
    PVC_LIST="$(kubectl get pvc -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')"
    #loop  over pvc
    if [[ "$PVC_LIST" == "" ]];
    then
        echo -e "\033[0;33mPersistent storage not configured\033[0m for namespace $NAMESPACE."
        return
    else
        echo  -e "\033[0;32mChecking persistent storage details in namespace $NAMESPACE..\033[0m"
        while read -r line;
        do
            separator
            PVC_NAME="$line"
            PVC_STATUS="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json | jq -r '.status.phase')"
            PVC_ACCESSMODE="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json | jq -r '.status.accessModes[]')"
            echo -e "\033[0;32mPVC $PVC_NAME: $PVC_STATUS\033[0m"
            pvc_check

            NAMESPACE_PV_LIST="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json | jq -r '.spec.volumeName')"
            separator
            #looping over pv
            while read -r line;
            do
                PV_NAME="$line"
                PV_STATUS="$(kubectl get pv "$PV_NAME" -o json | jq -r '.status.phase')"
                echo -e "\033[0;32mPV $PV_NAME: $PV_STATUS\033[0m" | sed 's/^/      /'
                COUNT=0
                pv_check | sed 's/^/      /'

                NS_CV_LIST="$(kubectl get cstorvolumes -A -o json | jq -r '.items[].metadata.name | select(. | contains("'$PV_NAME'"))')"
                if [ "$NS_CV_LIST" != "" ];
                then
                    separator
                    csp_check | sed "s/^/            /"
                    separator
                    echo -e "\033[0;32mcStorVolume status for namespace $NAMESPACE:\033[0m" | sed "s/^/            /"
                    COUNT=0
                    while read -r line;
                    do
                        CV_NAME="$line"
                        cstorvolume_check | sed "s/^/            /"
                    done <<< "$NS_CV_LIST"
                    message cStorVolume | sed "s/^/            /"
                fi

                NS_CVR_LIST="$(kubectl get cvr -A -o json | jq -r '.items[] | select(.metadata.labels."cstorvolume.openebs.io\/name" | contains("'$PV_NAME'")) | .metadata.name')"
                if [ "$NS_CVR_LIST" != "" ];
                then
                    separator
                    echo -e "\033[0;32mcStorVolumeReplica status for namespace $NAMESPACE:\033[0m" | sed "s/^/            /"
                    COUNT=0
                    while read -r line;
                    do
                        CVR_NAME="$line"
                        cvr_check | sed "s/^/            /"
                    done <<< "$NS_CVR_LIST"
                    message cStorVolumeReplica | sed "s/^/            /"
                fi
            done <<< "$NAMESPACE_PV_LIST"
        done <<< "$PVC_LIST"
    fi
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
            separator
            get_event () {
                LOGS="$(kubectl logs --tail=100 "$POD_NAME" -c "$line" --previous -n "$NAMESPACE"  |  grep -i  "warn\|error\|exception\|timeout|\retry\|unexpected\|denied\|IOException" | tail -3)"
                if [ "$LOGS" != "" ];
                then
                    echo -e "\033[0;32mLogs for restarted container $line:\033[0m" | sed "s/^/                /"
                    echo "$LOGS" | fold -w 70 -s| sed "s/^/                /"
                else
                    echo -e "\033[0;32mNo issues found in logs of container $line. Check the exit code.\033[0m" | sed "s/^/                /"
                fi
            }
            verbose && get_event
            COUNT=$((COUNT+1))
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
        pod_container_restart
        if ! verbose;
        then
            echo -e "Status found in kubectl get -o json pod $POD_NAME -n $NAMESPACE:" | sed "s/^/                /"
            echo -e "\033[0;33m$POD_STATE_CONTAINER_JSON\033[0m" | sed "s/^/                /"
        fi
    done <<< "$POD_STATE_CONTAINER_LIST"
}

pod_state_evicted () {
    POD_STATE_EVICT_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status')"
    echo -e "Reason of pod with status $STATUS:" | sed "s/^/                /"
    echo -e "\033[0;31m$POD_STATE_EVICT_JSON\033[0m" | sed "s/^/                /"
}

pod_state_pending () {
    POD_STATE_PENDING_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status')"
    echo -e "Reason of pod with status $STATUS:" | sed "s/^/                /"
    echo -e "\033[0;31m$POD_STATE_PENDING_JSON\033[0m" | sed "s/^/                /"
}

pod_state_init () {
    INIT_CONTAINER_NAME="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r '.status.initContainerStatuses[].name')"
    POD_LOG_INIT="$(kubectl logs "$POD_NAME" -n "$NAMESPACE" -c "$INIT_CONTAINER_NAME")"
    if verbose;
    then
        echo -e "Reason of pod with status $STATUS:" | sed "s/^/                /"
        echo "$POD_LOG_INIT" | fold -w 70 -s | sed "s/^/                /"
    fi
}

pod_state_imagepullbackoff () {
    POD_STATE_IMAGEPULLBAKCOFF_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status.containerStatuses[].state')"
    echo -e "Reason of pod with status $STATUS:" | sed "s/^/                /"
    echo -e "\033[0;31m$POD_STATE_IMAGEPULLBAKCOFF_JSON\033[0m" | sed "s/^/                /"
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
        if [[ "$STATUS" =~ "Init" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_init
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "ImagePullBackOff" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_imagepullbackoff
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "InvalidImageName" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_imagepullbackoff
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "Pending" ]];
        then
            echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
            pod_state_pending
            COUNT=$((COUNT+1))
        fi
        if [[ "$STATUS" == "Running" ]];
        then
            CONTAINERS_RUNNING="$(echo "$line" | awk '{print $2}')"
            if [[ "$RESTART" -gt 0 ]];
            then
                echo -e "\033[1;33m! [WARNING] pod\033[0m" "$POD_NODE"/"$POD_NAME" is "\033[1;32mRunning\033[0m" since "$POD_AGE", having containers restarted.
                pod_container_restart
            else
                if [[ "$(echo "$CONTAINERS_RUNNING" | awk -F '/' '{print $1}')" ==  "$(echo "$CONTAINERS_RUNNING" | awk -F '/' '{print $2}')" ]];
                then
                    verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pod\033[0m" "$POD_NAME" "$POD_NODE"
                else
                    echo -e "\033[1;33m! [WARNING] pod\033[0m" "$POD_NODE"/"$POD_NAME" is "\033[1;32mRunning\033[0m" since "$POD_AGE", \
                    with all containers not in running state. "\033[1;33mIt may take some time for all containers to come up.\033[0m"
                fi
            fi
        fi
    done <<< "$POD_LIST"
    message pods
}

rs () {
    COUNT=0
    echo -e "\033[0;32mReplicaSet details:\033[0m"
    separator
    RS_LIST="$(kubectl get rs -n "$NAMESPACE" --no-headers | awk '{if($2!=0) print}' 2> /dev/null)"
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
    message replicaSets
    separator
}

debug_ns() {
    [ "$KUBECONFIG" == "" ] && echo "Please set KUBECONFIG for the cluster." && exit
    [ -x jq ] && echo "Command 'jq' not found. Please install it." >&2 && exit 1
    check_namespace
    clear
    echo "-------------------------------------------------------------"
    echo -e "\033[0;32mCrawling objects in namespace $NAMESPACE:\033[0m"
    echo "-------------------------------------------------------------"
    rs
    pods
    peristent_storage
    ! verbose && echo "Run script  with '-v' flag to get more details.."
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
debug_ns

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo Total time taken: "$EXECUTION_TIME"s