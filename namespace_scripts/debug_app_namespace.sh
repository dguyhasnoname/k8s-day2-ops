#!/bin/bash
#shellcheck disable=SC2086,SC2059
##########################################################################
# This script finds all possible issues in namespace.                    #
# Author: Mukund                                                         #
# Date: 29th August 2019                                                 #
# Version: 1.0                                                           #
##########################################################################

START_TIME=$(date +%s)
NAMESPACE=${1:-kube-system}
FLAG="$2"
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BOLD='\033[1;30m'
NC='\033[0m'
TICK='\xE2\x9C\x94'

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
        echo -e "${GREEN}${TICK}           \033[0m"no issues found for "$OBJECT".
    else
        echo -e "\033[1;31;5m[ALERT!]    \033[0m"issues found for "$OBJECT"!
    fi
    separator
}

check_namespace() {
    echo "Validating namespace $NAMESPACE ..."
    NS_VALIDATION="$(kubectl get ns/"$NAMESPACE")"
    [ "$NS_VALIDATION" != "" ] && echo -en "\033[0;32mNamespace $NAMESPACE found.\033[0m" && echo " Fetching objects in namespace $NAMESPACE..."
    [ "$NS_VALIDATION" == "" ] && echo -e "${RED}[ERROR]\033[0m" Namespace "$NAMESPACE" was not found! Please provide correct namespace. && exit
}

pvc_check () {
    if [[ "$PVC_STATUS" != "Bound" ]];
    then
        echo -e "\033[1;33m! [WARNING] pvc\033[0m" "$line"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "${GREEN}${TICK} [OK]      pvc\033[0m" "$PVC_NAME"
    fi
    message pvc
}

pv_check () {
    if [[ "$PV_STATUS" != "Bound" ]];
    then
        echo -e "\033[1;33m! [WARNING] pv\033[0m" "$line"
        COUNT=$((COUNT+1))
    else
        verbose && echo -e "${GREEN}${TICK} [OK]      pv\033[0m" "$line"
    fi
    message pv
}

csp_check () {
    COUNT=0
    CSP_LIST="$(echo "$CSP_JSON" | jq -r '.items[].metadata.name')"
    CST_GET_DETAIL="$(kubectl get csp --no-headers)"
    if [[ "$CSP_LIST" != "" ]];
    then
        [ "$NAMESPACE" != "openebs" ] && echo -e "\033[0;32mcStor configuration found for namespace $NAMESPACE..\033[0m"
        while read -r line;
        do
            CSP_NAME="$line"
            CSP_STATUS="$(echo "$CSP_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CSP_NAME'")) | .status.phase')"
            if [[ "$CSP_STATUS" != "Healthy" ]];
            then
                echo -e "\033[1;33m! [WARNING] csp_check\033[0m" "$(echo "$CST_GET_DETAIL" | grep "$CSP_NAME")"
                COUNT=$((COUNT+1))
            else
                echo -e "${GREEN}${TICK} [OK]      CstorPool\033[0m" "$(echo "$CST_GET_DETAIL" | grep "$CSP_NAME")"
            fi
        done <<< "$CSP_LIST"
        message cStorPool
    fi
}

cstorvolume_check () {
    COUNT=0
    replica_check () {
        if [[ "$NAMESPACE" != "openebs" ]];
        then
            verbose && echo "$CV_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$PV_NAME'")) | "Specs:", .spec, "Replica status:", .status.replicaStatuses[]' | indent 24
        else
            CV_PV_NAME="$(echo "$OPENEBS_PV_JSON" | jq -r '.items[] | select(.metadata.name=="'$CV_NAME'") | .metadata.name')"
            CV_PV_DETAIL="$(echo "$OPENEBS_PV_JSON" | jq -rj '.items[] | select(.metadata.name=="'$CV_PV_NAME'") | .spec | "PVC Name: ", .claimRef.name, "/", .accessModes[]')"
            echo -e "\033[1;30mPV Name:\033[0m $CV_PV_NAME" | indent 24
            echo -e "$CV_PV_DETAIL" | indent 24
            verbose && echo "$CV_STATUS_JSON"| jq -r '.items[] | select(.metadata.name | contains("'$CV_NAME'")) | "Specs:", .spec, "Replica status:", .status.replicaStatuses[]' | indent 24
        fi
    }
    if [[ "$NAMESPACE" != "openebs" ]];
    then
        CV_STATUS="$(echo "$CV_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$PV_NAME'")) | .status.phase' )"
    else
        CV_STATUS="$(echo "$CV_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CV_NAME'")) | .status.phase' )"
    fi
    CV_GET_DETAILS="$(kubectl get cstorvolume -A)"
    if [[ "$CV_STATUS" != "Healthy" ]];
    then
        echo -e "${RED}\xE2\x9D\x8C[ERROR]    CStorVolume\033[0m" "$(echo "$CV_GET_DETAILS" | grep "$CV_NAME" )"
        replica_check
        COUNT=$((COUNT+1))
    elif [[ "$CV_STATUS" == "Offline" ]];
    then
        echo -e "\033[1;33m! [WARNING]  CStorVolume\033[0m" "$(echo "$CV_GET_DETAILS" | grep "$CV_NAME" )"
        replica_check
        COUNT=$((COUNT+1))
    else
        echo -e "${GREEN}${TICK} [OK]      CstorVolume\033[0m" "$(echo "$CV_GET_DETAILS" | grep "$CV_NAME" )"
        replica_check
    fi
}

cvr_check () {
    CVR_STATUS="$(echo "$CVR_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CVR_NAME'")) | .status.phase')"
    if [[ "$CVR_STATUS" != "Healthy" ]];
    then
        echo -e "${RED}\xE2\x9D\x8C[ERROR]    CStorVolumeReplica\033[0m" "$CVR_DETAIL"
        COUNT=$((COUNT+1))
    elif [[ "$CVR_STATUS" == "Offline" ]];
    then
        echo -e "\033[1;33m! [WARNING] CStorVolumeReplica\033[0m" "$CVR_DETAIL"
        COUNT=$((COUNT+1))
    else
        echo -e "${GREEN}${TICK} [OK]      CstorVolumeReplica\033[0m" "$CVR_DETAIL"
    fi
}

peristent_storage () {
    separator
    COUNT=0
    PVC_LIST="$(kubectl get pvc -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')"
    #loop over pvc
    if [[ "$PVC_LIST" == "" ]];
    then
        echo -e "\033[0;33mPersistent storage not configured\033[0m for namespace $NAMESPACE."
        return
    else
        echo  -e "\033[1;35mChecking persistent storage details in namespace $NAMESPACE..\033[0m"
        while read -r line;
        do
            separator
            PVC_NAME="$line"
            PVC_JSON="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json)"
            PVC_STATUS="$(echo "$PVC_JSON" | jq -r '.status.phase')"
            PVC_ACCESSMODE="$(echo "$PVC_JSON" | jq -r '.status.accessModes[]')"
            PVC_CAPACITY="$(echo "$PVC_JSON" | jq -r '.status.capacity.storage')"
            echo -e "\033[0;32mPVC $PVC_NAME: $PVC_STATUS\033[0m" "$PVC_ACCESSMODE" "$PVC_CAPACITY"
            pvc_check

            NAMESPACE_PV_LIST="$(echo "$PVC_JSON" | jq -r '.spec.volumeName')"
            separator
            #looping over pv
            while read -r line;
            do
                PV_NAME="$line"
                PV_STATUS="$(kubectl get pv "$PV_NAME" -o json | jq -r '.status.phase')"
                echo -e "\033[0;32mPV $PV_NAME: $PV_STATUS\033[0m" | indent 6
                COUNT=0
                pv_check | indent 6

                CV_STATUS_JSON="$(kubectl get cstorvolume -A -o json)"
                NS_CV_LIST="$(echo "$CV_STATUS_JSON" | jq -r '.items[].metadata.name | select(. | contains("'$PV_NAME'"))')"
                if [ "$NS_CV_LIST" != "" ];
                then
                    separator
                    CSP_JSON="$(kubectl get csp -o json)"
                    csp_check | indent 12
                    separator
                    echo -e "\033[0;32mcStorVolume status for namespace $NAMESPACE:\033[0m" | indent 12
                    COUNT=0
                    while read -r line;
                    do
                        CV_NAME="$line"
                        cstorvolume_check | indent 12
                    done <<< "$NS_CV_LIST"
                    message cStorVolume | indent 12
                fi

                CVR_STATUS_JSON="$(kubectl get cvr -A -o json)"
                CVR_GET_DETAILS="$(kubectl get cvr -A --no-headers)"
                NS_CVR_LIST="$(echo "$CVR_STATUS_JSON" | jq -r '.items[] | select(.metadata.labels."cstorvolume.openebs.io\/name" | contains("'$PV_NAME'")) | .metadata.name')"
                if [ "$NS_CVR_LIST" != "" ];
                then
                    separator
                    echo -e "\033[0;32mcStorVolumeReplica status for namespace $NAMESPACE:\033[0m" | indent 12
                    COUNT=0
                    while read -r line;
                    do
                        CVR_NAME="$line"
                        CVR_DETAIL="$(echo "$CVR_GET_DETAILS" | grep "$CVR_NAME" )"
                        cvr_check | indent 12
                    done <<< "$NS_CVR_LIST"
                    message cStorVolumeReplica | indent 12
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
            echo -e "Container \033[1;33m$line\033[0m restart count: $RESTART" | indent 16
            echo "$CONTAINER_JSON" | awk '{printf "'${RED}'%-10s'${NC}' %-5s %-25s %-25s\n", $1, $2, $3, $4}' | indent 16
            separator
            get_logs () {
                LOGS="$(kubectl logs --tail=100 "$POD_NAME" -c "$line" --previous -n "$NAMESPACE"  |  grep -i  "warn\|error\|exception\|timeout|\retry\|unexpected\|denied\|IOException" | tail -3)"
                if [ "$LOGS" != "" ];
                then
                    echo -e "\033[0;32mLogs for previous restarted container $line:\033[0m" | indent 16
                    echo -e "\033[0;31m$LOGS\033[0m" | fold -w 70 -s| indent 16
                else
                    echo -e "\033[0;32mNo issues found in logs of container $line. Check the exit code.\033[0m" | indent 16
                fi
            }
            verbose && get_logs
            COUNT=$((COUNT+1))
        else
            echo -e "Container \033[1;33m$line\033[0m restart count: $RESTART" | indent 16
            if [[ "$(echo "$POD_JSON" | jq -r '.status.containerStatuses[].lastState[]')" == "" ]];
            then
                echo -e "status.containerStatuses.lastState: \033[0;31mnull\033[0m" | indent 16
                #echo -e "Container $line was last terminated with exitCode: \033[0;32m0\033[0m and reason: \033[0;32mCompleted\033[0m " | indent 16
                if verbose;
                then
                    EVENTS="$(kubectl describe po "$POD_NAME" -n "$NAMESPACE" | grep -A10 -w Events)"
                    echo -e "\033[0;31m$EVENTS\033[0m" | indent 16
                fi
            fi
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
            echo -e "Status found in kubectl get -o json pod $POD_NAME -n $NAMESPACE:" | indent 16
            echo -e "\033[0;33m$POD_STATE_CONTAINER_JSON\033[0m" | indent 16
        fi
    done <<< "$POD_STATE_CONTAINER_LIST"
}

pod_state_evicted () {
    POD_STATE_EVICT_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status')"
    echo -e "Reason of pod with status $STATUS:" | indent 16
    echo -e "\033[0;31m$POD_STATE_EVICT_JSON\033[0m" | indent 16
}

pod_state_pending () {
    POD_STATE_PENDING_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status')"
    echo -e "Reason of pod with status $STATUS:" | indent 16
    echo -e "\033[0;31m$POD_STATE_PENDING_JSON\033[0m" | indent 16
}

pod_state_init () {
    INIT_CONTAINER_NAME="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r '.status.initContainerStatuses[].name')"
    POD_LOG_INIT="$(kubectl logs "$POD_NAME" -n "$NAMESPACE" -c "$INIT_CONTAINER_NAME")"
    if verbose;
    then
        echo -e "Reason of pod with status $STATUS:" | indent 16
        echo "$POD_LOG_INIT" | fold -w 70 -s | indent 16
    fi
}

pod_state_imagepullbackoff () {
    POD_STATE_IMAGEPULLBAKCOFF_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status.containerStatuses[].state')"
    echo -e "Reason of pod with status $STATUS:" | indent 16
    echo -e "\033[0;31m$POD_STATE_IMAGEPULLBAKCOFF_JSON\033[0m" | indent 16
}

pod_state_containercreating () {
    POD_STATE_CONTAINER_CREATING_JSON="$(kubectl get events -o json -n "$NAMESPACE" | jq '.items[].message')"
    echo -e "Reason of pod with status $STATUS:" | indent 16
    echo -e "\033[0;31m$POD_STATE_CONTAINER_CREATING_JSON\033[0m" | indent 16
}

pod_state_terminating () {
    POD_STATE_CONTAINER_TERMINATING_JSON="$(kubectl get pods "$POD_NAME" -o json -n "$NAMESPACE" | jq -r  '.status.conditions[].message | select(.!=null)')"
    echo -e "\033[0;31m$POD_STATE_CONTAINER_TERMINATING_JSON\033[0m" | indent 16
}

pods () {
    COUNT=0
    echo -e "\033[1;35mPod details:\033[0m"
    separator
    POD_LIST="$(kubectl get pods -o wide --no-headers -n "$NAMESPACE" 2> /dev/null)"
    if [[ "$POD_LIST" == "" ]];then
        echo -e "\033[1;33m! [WARNING]    \033[0m 0 pods running in namespace $NAMESPACE."
        return
    else
        POD_COUNT="$(echo "$POD_LIST" | wc -l)"
        echo -e "${GREEN}${TICK}           pods found:$POD_COUNT\033[0m"
    fi
    while read -r line;
    do
        STATUS="$(echo "$line" | awk '{print $3}')"
        POD_NAME="$(echo "$line" | awk '{print $1}')"
        POD_NODE="$(echo "$line" | awk '{print $7}')"
        RESTART="$(echo "$line" | awk '{print $4}')"

        call_pod_fun () {
            if [[ "$STATUS" == "$1" ]];
            then
                echo -e "${RED}\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
                "$2"
                COUNT=$((COUNT+1))
            fi
        }

        call_pod_fun CrashLoopBackOff pod_state_crashloopbackoff
        call_pod_fun Evicted pod_state_evicted
        call_pod_fun CreateContainerConfigError pod_state_crashloopbackoff
        call_pod_fun Init pod_state_init
        call_pod_fun ImagePullBackOff pod_state_imagepullbackoff
        call_pod_fun InvalidImageName pod_state_imagepullbackoff
        call_pod_fun Pending pod_state_pending
        call_pod_fun ContainerCreating pod_state_containercreating
        call_pod_fun Terminating pod_state_terminating

        if [[ "$STATUS" == "Completed" ]];
        then
            verbose && echo -e "${GREEN}${TICK} [OK]      pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
        fi

        if [[ "$STATUS" == "Running" ]];
        then
            CONTAINERS_RUNNING="$(echo "$line" | awk '{print $2}')"
            if [[ "$RESTART" -gt 0 ]];
            then
                echo -e "\033[1;33m! [WARNING] pod\033[0m" "$line"
                pod_container_restart
            else
                if [[ "$(echo "$CONTAINERS_RUNNING" | awk -F '/' '{print $1}')" ==  "$(echo "$CONTAINERS_RUNNING" | awk -F '/' '{print $2}')" ]];
                then
                    verbose && echo -e "${GREEN}${TICK} [OK]      pod\033[0m" "$line"
                else
                    echo -e "\033[1;33m! [WARNING] pod\033[0m" "$line"
                    separator
                    echo "Events in the name space $NAMESPACE:" | indent 16
                    EVENTS="$(kubectl get events -o json -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp --field-selector type!=Normal | jq '.items[].message')"
                    echo -e "\033[0;31m$EVENTS\033[0m" | fold -w 70 -s | indent 16
                    COUNT=$((COUNT+1))
                fi
            fi
        fi
    done <<< "$POD_LIST"
    message pods
}

rs () {
    COUNT=0
    echo -e "\033[1;35mReplicaSet details:\033[0m"
    separator
    RS_LIST="$(kubectl get rs -n "$NAMESPACE" --no-headers | awk '{if($2!=0) print}' 2> /dev/null)"
    if [[ "$RS_LIST" == "" ]];
    then
        echo -e "\033[1;33m! [WARNING]    \033[0m 0 replicasets running in namespace $NAMESPACE."
        return
    else
        RS_COUNT="$(echo "$RS_LIST" | wc -l)"
        echo -e "${GREEN}${TICK}           replicaset found:$RS_COUNT\033[0m"
    fi
    while read -r line;
    do
        if [[ "$(echo "$line" | awk '{print $2}')" != "$(echo "$line" | awk '{print $4}')" ]];
        then
            echo -e "\033[1;33m! [WARNING] replicaset\033[0m" "$line"
            COUNT=$((COUNT+1))
        else
            verbose && echo -e "${GREEN}${TICK} [OK]      replicaset\033[0m" "$line"
        fi
    done <<< "$RS_LIST"
    message replicaSets
}

ns_quota () {
    separator
    echo -e "${GREEN}${TICK}           namespace quota:\033[0m"
    kubectl describe ns "$NAMESPACE" | sed -n '/Resource Quotas/,/Resource Limits/{//!p;}' | indent 11
}

velero_backup () {
    separator
    VELERO_BACKUP_JSON="$(velero backup get -o json)"
    VELERO_BACKUP_LIST="$(echo "$VELERO_BACKUP_JSON" | jq -r '.items[].metadata.name')"
    if [[ "$VELERO_BACKUP_LIST" != "" ]];
    then
        printf "\033[1;35mVelero backups details: \033[0m\n"
        separator
        printf "${GREEN}${TICK}           velero backups found: \033[0m $(echo "$VELERO_BACKUP_LIST" | wc -l)\n"
        while read -r line;
        do
            VELERO_BACKUP_STATUS="$(echo "$VELERO_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name == "'$line'") | .status.phase')"
            VELERO_BACKUP_NAMESPACE="$(echo "$VELERO_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name == "'$line'") | .spec.includedNamespaces[]')"
            if [[ "$VELERO_BACKUP_STATUS" != "Completed" ]];
            then
                printf "\033[1;33m! [WARNING] backup\033[0m $line  status: ${RED}$VELERO_BACKUP_STATUS\033[0m for namespace $VELERO_BACKUP_NAMESPACE\n"
                echo "$VELERO_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name == "'$line'") | .status' | indent 16
                COUNT=$((COUNT+1))
            else
                verbose && printf "${GREEN}${TICK} [OK]      backup\033[0m $line status: ${GREEN}$VELERO_BACKUP_STATUS\033[0m for namespace $VELERO_BACKUP_NAMESPACE\n"
            fi
        done <<< "$VELERO_BACKUP_LIST"
    fi
    message "velero backup"
}

openebs_component_pod () {
    data_plane_relation () {
        COMPONENT_POD_PV="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .metadata.labels."openebs.io\/persistent-volume"')"
        COMPONENT_POD_PVC="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .metadata.labels."openebs.io\/persistent-volume-claim"')"
        COMPONENT_POD_STORAGE_CLASS="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .metadata.labels."openebs.io\/storage-class"')"

        if [[ "$TYPE" == "data" ]];
        then
            echo -e "\033[0;32mPV:\033[0m" "$COMPONENT_POD_PV" | indent 4
            echo -e "\033[0;32mPVC:\033[0m" "$COMPONENT_POD_PVC" | indent 4
            echo -e "\033[0;32mStorage class:\033[0m" "$COMPONENT_POD_STORAGE_CLASS" | indent 4
        fi
    }
    TYPE="$1"
    while read -r line;
    do
        COMPONENT_POD_NAME="$line"
        COMPONENT_POD_STATUS="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .status.phase')"
        COMPONENT_POD_RESTART_COUNT="$(echo "$POD_DETAIL" | grep "$COMPONENT_POD_NAME" | awk '{print $4}')"
        if (( ! "$COMPONENT_POD_RESTART_COUNT" >= 1 )) && [[ "$COMPONENT_POD_STATUS" == "Running" ]];
        then
            echo -e "${GREEN}${TICK} [OK]      pod\033[0m" "$(echo "$POD_DETAIL" | grep "$COMPONENT_POD_NAME" | awk '{$(NF)="";$(NF-1)="";print $0}')"
            [[ "$COMPONENT_POD_NAME" =~ "target" ]] && data_plane_relation | indent 12
        else
            echo -e "\033[1;33m! [WARNING] pod\033[0m" "$(echo "$POD_DETAIL" | grep "$COMPONENT_POD_NAME" | awk '{$(NF)="";$(NF-1)="";print $0}')"
            [[ "$COMPONENT_POD_NAME" =~ "target" ]] && data_plane_relation | indent 12
            COUNT=$((COUNT+1))
        fi
    done <<< "$COMPONENT_POD_LIST"
}

openebs_control_plane () {
    separator
    COUNT=0
    printf "\033[1;32mChecking control plane components for OpenEBS..\033[0m\n"
    OPENEBS_CONTROL_PLANE_LIST="$(echo "$OPENEBS_JSON" | jq -r '.items[].metadata.labels."openebs.io\/component-name"|select(.!=null)' | awk '!seen[$0]++')"
    OPENEBS_CONTROL_PLANE_PODS_TOTAL="$(echo "$OPENEBS_JSON" | jq -r '.items[].metadata.labels."openebs.io\/component-name"|select(.!=null)' | wc -l)"
    printf "${GREEN}${TICK}           control plane components found: \033[0m $(echo "$OPENEBS_CONTROL_PLANE_LIST" | wc -l)" "($OPENEBS_CONTROL_PLANE_PODS_TOTAL pods)\n"
    separator
    while read -r line;
    do
        COMPONENT_NAME="$line"
        COMPONENT_POD_LIST="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels."openebs.io\/component-name"=="'$COMPONENT_NAME'") | .metadata.name')"
        printf "\033[1;35m$line:\033[0m\n"
        openebs_component_pod
        separator
    done <<< "$OPENEBS_CONTROL_PLANE_LIST"
    message "control plane components"
}

openebs_data_plane () {
    separator
    COUNT=0
    printf "\033[1;32mChecking data plane components for OpenEBS..\033[0m\n"
    CSTOR_POOL_LIST="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels.app=="cstor-pool") | .metadata.name')"
    CSTOR_VOL_MANAGER="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels.app=="cstor-volume-manager") | .metadata.name')"
    JIVA_CONTROLLER="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels."openebs.io\/controller"=="jiva-controller") | .metadata.name')"
    JIVA_REPLICA="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels."openebs.io\/replica"=="jiva-replica") | .metadata.name')"
    NFS_PROVISIONER="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels.app=="openebs-nfs-provisioner") | .metadata.name')"
    echo -e "${GREEN}${TICK}           date plane components found: 5\033[0m"

    data_plane_comp_details () {
        if [[ "$1" != "" ]];
        then
            COMPONENT_NAME="$2"
            COMPONENT_POD_LIST="$1"
            printf "\033[1;35m$COMPONENT_NAME: $(echo "$1" | wc -l)\033[0m\n"
            openebs_component_pod "$3"
            separator
        else
            printf "\033[1;33m! [WARNING] $COMPONENT_NAME\033[0m not found.\n"
            openebs_component_pod "$3"
            separator
        fi
        message "$COMPONENT_NAME"
    }

    data_plane_comp_details "$CSTOR_POOL_LIST" cstor-pool
    data_plane_comp_details "$CSTOR_VOL_MANAGER" cstor-volume-manager data
    data_plane_comp_details "$JIVA_CONTROLLER" jiva-controller
    data_plane_comp_details "$JIVA_REPLICA" jiva-replica
    data_plane_comp_details "$NFS_PROVISIONER" openebs-nfs-provisioner
}

openebs_sp () {
    separator
    printf "\033[1;35mStorage pools:\033[0m\n"
    OPENEBS_SP_JSON="$(kubectl get sp -o json)"
    OPENEBS_SP_LIST="$(echo "$OPENEBS_SP_JSON" | jq -r '.items[].metadata.name')"
    printf "${GREEN}${TICK}           storage pools found:\033[0m $(echo "$OPENEBS_SP_LIST" | wc -l)\n"
    while read -r line;
    do
        OPENEBS_SP_NAME="$line"
        OPENEBS_SP_PATH="$(echo "$OPENEBS_SP_JSON" | jq -r '.items[] | select(.metadata.name=="'$OPENEBS_SP_NAME'") | .spec.path')"
        printf "\033[0;32m%-15s %-30s\033[0m\n" "$OPENEBS_SP_NAME:" "$OPENEBS_SP_PATH" | indent 12
    done <<< "$OPENEBS_SP_LIST"
}

openebs_spc () {
    separator
    printf "\033[1;35mStorage pool claims:\033[0m\n"
    OPENEBS_SPC_JSON="$(kubectl get spc -o json)"
    OPENEBS_SPC_LIST="$(echo "$OPENEBS_SPC_JSON" | jq -r '.items[].metadata.name')"
    printf "${GREEN}${TICK}           storagepool claims found:\033[0m $(echo "$OPENEBS_SPC_LIST" | wc -l)\n"
    while read -r line;
    do
        OPENEBS_SPC_NAME="$line"
        OPENEBS_SPC_STATUS="$(echo "$OPENEBS_SPC_JSON" | jq -r '.items[] | select(.metadata.name=="'$OPENEBS_SPC_NAME'") | .status.phase')"
        printf "\033[0;32m%-25s %-30s\033[0m\n" "$OPENEBS_SPC_NAME" "$OPENEBS_SPC_STATUS" | indent 12
    done <<< "$OPENEBS_SPC_LIST"
}

openebs_sc () {
    separator
    printf "\033[1;35mStorage class:\033[0m\n"
    OPENEBS_SC_JSON="$(kubectl get sc -o json)"
    OPENEBS_SC_LIST="$(echo "$OPENEBS_SC_JSON" | jq -r '.items[].metadata.name')"
    printf "${GREEN}${TICK}           storage-class found:\033[0m $(echo "$OPENEBS_SC_LIST" | wc -l)\n"
    printf "${BOLD}%-25s %-30s %-15s %-10s\033[0m\n" Name Provisioner reclaimPolicy PVCs| indent 12
    OPENEBS_PV_JSON="$(kubectl get pvc -A -o json)"
    while read -r line;
    do
        OPENEBS_SC_NAME="$line"
        OPENEBS_SC_PROVISIONER="$(echo "$OPENEBS_SC_JSON" | jq -r '.items[] | select(.metadata.name=="'$OPENEBS_SC_NAME'") | .provisioner')"
        OPENEBSE_SC_DETAIL="$(echo "$OPENEBS_SC_JSON" | jq -r '.items[] | select(.metadata.name=="'$OPENEBS_SC_NAME'") | .reclaimPolicy')"
        OPENEBS_SC_PV_LIST="$(echo "$OPENEBS_PV_JSON" | jq -r '.items[] | select(.metadata.annotations."volume.beta.kubernetes.io\/storage-class"=="'$OPENEBS_SC_NAME'") | .metadata.name')"

        printf "\033[0;32m%-25s %-30s %-15s %-5s\033[0m\n" "$OPENEBS_SC_NAME" "$OPENEBS_SC_PROVISIONER" "$OPENEBSE_SC_DETAIL" "$(echo "$OPENEBS_SC_PV_LIST" | wc -l)"| indent 12
        if [[ "$OPENEBS_SC_PV_LIST" != "" ]] && verbose ;
        then
            echo "PVCs found for this storage class:"  | indent 19
            echo "$OPENEBS_SC_PV_LIST" | indent 24
        fi
    done <<< "$OPENEBS_SC_LIST"
}

openebs_csp () {
    separator
    printf "\033[1;35mStorage cStorPool:\033[0m\n"
    CSP_JSON="$(kubectl get csp -o json)"
    CSP_LIST="$(echo "$CSP_JSON" | jq -r '.items[].metadata.name')"
    printf "${GREEN}${TICK}           cStorPool found:\033[0m $(echo "$CSP_LIST" | wc -l)\n"
    printf "NAME         USED    FREE   TOTAL  STATUS    TYPE      AGE" | indent 22
    [[ "$CSP_LIST" != "" ]] && csp_check
}

openebs_cv () {
    separator
    printf "\033[1;35mStorage cstorvolumes:\033[0m\n"
    CV_STATUS_JSON="$(kubectl get cstorvolumes -A -o json)"
    CV_LIST="$(echo "$CV_STATUS_JSON" | jq -r '.items[].metadata.name')"
    printf "${GREEN}${TICK}           cStorVolumes found:\033[0m $(echo "$CV_LIST" | wc -l)\n"
    OPENEBS_PV_JSON="$(kubectl get pv -o json -n openebs)"
    if [[ "$CV_LIST" != "" ]];
    then
        while read  -r line;
        do
            CV_NAME="$line"
            cstorvolume_check
        done <<< "$CV_LIST"
        message cStorVolumes
    fi
}

openebs_cvr () {
    separator
    CVR_STATUS_JSON="$(kubectl get cvr -A -o json)"
    CVR_LIST="$(echo "$CVR_STATUS_JSON" | jq -r '.items[] | .metadata.name')"
    printf "${GREEN}${TICK}           cStorVolumeReplicas found:\033[0m $(echo "$CVR_LIST" | wc -l)\n"
    if [[ "$CVR_LIST" != "" ]];
    then
        CVR_GET_DETAILS="$(kubectl get cvr -A --no-headers)"
        CVR_PV_JSON="$(kubectl get pv -A -o json)"
        while read  -r line;
        do
            CVR_NAME="$line"
            CVR_DETAIL="$(echo "$CVR_GET_DETAILS" | grep "$CVR_NAME" )"
            cvr_check
            if verbose;
            then
                CVR_PV_NAME="$(echo "$CVR_STATUS_JSON" | jq -r '.items[] | select(.metadata.name=="'$CVR_NAME'") | .metadata.labels."openebs.io\/persistent-volume"')"
                CVR_PV_DETAIL="$(echo "$CVR_PV_JSON" | jq -rj '.items[] | select(.metadata.name=="'$CVR_PV_NAME'") | .spec | "PVC Name: ", .claimRef.name, "  ", .accessModes[]')"
                echo -e "\033[0;32mPV Name\033[0m:" "$CVR_PV_NAME" | indent 31
                if [[ "$CVR_PV_DETAIL" != "" ]];
                then
                    echo -e "${BOLD}$CVR_PV_DETAIL\033[0m" | indent 31
                else
                    echo -e "\033[1;30mPVC Name: null\033[0m" | indent 31
                fi
            fi
        done <<< "$CVR_LIST"
        message cStorVolumeReplicas
    fi
}

openebs_blockdevices () {
    separator
    COUNT=0
    printf "\033[1;35mBlock devices:\033[0m\n"
    BLOCK_DEVICE_JSON="$(kubectl get blockdevices -n openebs -o json)"
    BLOCK_DEVICE_LIST="$(echo "$BLOCK_DEVICE_JSON" | jq -r '.items[] | .metadata.name')"
    printf "${GREEN}${TICK}           blockdevices found:\033[0m $(echo "$BLOCK_DEVICE_LIST" | wc -l)\n"
    if [[ "$BLOCK_DEVICE_LIST" != "" ]];
    then
        while read -r line;
        do
            BLOCK_DEVICE_NAME="$line"
            BLOCK_DEVICE_STATUS="$(echo "$BLOCK_DEVICE_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_NAME'")) | .status.state')"
            BLOCK_DEVICE_CLAIM_STATE="$(echo "$BLOCK_DEVICE_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_NAME'")) | .status.claimState')"
            BLOCK_DEVICE_HOST="$(echo "$BLOCK_DEVICE_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_NAME'")) | .metadata.labels."kubernetes.io\/hostname"')"
            if [[ "$BLOCK_DEVICE_STATUS" == "Active" && "$BLOCK_DEVICE_CLAIM_STATE" == "Claimed" ]];
            then
                printf "${GREEN}${TICK}%-10s %-45s\033[0m %-20s %-8s %-10s\n" " [OK]" "$BLOCK_DEVICE_NAME" "$BLOCK_DEVICE_HOST" "$BLOCK_DEVICE_STATUS" "$BLOCK_DEVICE_CLAIM_STATE"
            else
                printf "\033[1;33m%-11s %-45s\033[0m %-20s %-8s %-10s\n" "! [WARNING]" "$BLOCK_DEVICE_NAME" "$BLOCK_DEVICE_HOST" "$BLOCK_DEVICE_STATUS" "$BLOCK_DEVICE_CLAIM_STATE"
                COUNT=$((COUNT+1))
            fi
        done <<< "$BLOCK_DEVICE_LIST"
    fi
    message blockdevices
}

openebs_blockdeviceclaims () {
    COUNT=0
    separator
    printf "\033[1;35mBlock device claims:\033[0m\n"
    BLOCK_DEVICE_CLAIM_JSON="$(kubectl get blockdeviceclaims -n openebs -o json)"
    BLOCK_DEVICE_CLAIM_LIST="$(echo "$BLOCK_DEVICE_CLAIM_JSON" | jq -r '.items[] | .metadata.name')"
    printf "${GREEN}${TICK}           blockdevices found:\033[0m $(echo "$BLOCK_DEVICE_CLAIM_LIST" | wc -l)\n"
    if [[ "$BLOCK_DEVICE_CLAIM_LIST" != "" ]];
    then
        while read -r line;
        do
            BLOCK_DEVICE_CLAIM_NAME="$line"
            BLOCK_DEVICE_CLAIM_STATUS="$(echo "$BLOCK_DEVICE_CLAIM_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_CLAIM_NAME'")) | .status.phase')"
            BLOCK_DEVICE_CLAIM_SPC="$(echo "$BLOCK_DEVICE_CLAIM_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_CLAIM_NAME'")) | .metadata.labels."openebs.io\/storage-pool-claim"')"
            BLOCK_DEVICE_CLAIM_HOST="$(echo "$BLOCK_DEVICE_CLAIM_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_CLAIM_NAME'")) | .spec.hostName')"
            BLOCK_DEVICE_NAME="$(echo "$BLOCK_DEVICE_CLAIM_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$BLOCK_DEVICE_CLAIM_NAME'")) | .spec.blockDeviceName')"
            if [[ "$BLOCK_DEVICE_CLAIM_STATUS" == "Bound" ]];
            then
                verbose && printf "${GREEN}${TICK}%-10s %-45s\033[0m %-20s %-8s %-10s\n" " [OK]" "$BLOCK_DEVICE_CLAIM_NAME" "$BLOCK_DEVICE_CLAIM_HOST" "$BLOCK_DEVICE_CLAIM_STATUS" "$BLOCK_DEVICE_CLAIM_SPC" \
                && printf "Block device name: $BLOCK_DEVICE_NAME" | indent 12
            else
                printf "${GREEN}${TICK}%-10s %-45s\033[0m %-20s %-8s %-10s\n" " [OK]" "$BLOCK_DEVICE_CLAIM_NAME" "$BLOCK_DEVICE_CLAIM_HOST" "$BLOCK_DEVICE_CLAIM_STATUS" "$BLOCK_DEVICE_CLAIM_SPC"
                verbose && printf "Block device name: $BLOCK_DEVICE_NAME" | indent 12
                COUNT=$((COUNT+1))
            fi
        done <<< "$BLOCK_DEVICE_CLAIM_LIST"
    fi
    message blockdeviceclaims
}

cstorbackups () {
    COUNT=0
    separator
    printf "\033[1;35mcStor backups:\033[0m\n"
    CSTOR_BACKUP_JSON="$(kubectl get cstorbackups -n openebs -o json)"
    CSTOR_BACKUP_LIST="$(echo "$CSTOR_BACKUP_JSON" | jq -r '.items[] | .metadata.name')"
    CSTOR_BACKUP_COUNT="$(echo "$CSTOR_BACKUP_LIST" | wc -l)"
    printf "${GREEN}${TICK}           cstorbackups found:\033[0m $CSTOR_BACKUP_COUNT\n"
    if [[ "$CSTOR_BACKUP_LIST" != "" ]];
    then
        while read -r line;
        do
            CSTOR_BACKUP_NAME="$line"
            CSTOR_BACKUP_STATUS="$(echo "$CSTOR_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CSTOR_BACKUP_NAME'")) | .status')"
            CSTOR_SPEC="$(echo "$CSTOR_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CSTOR_BACKUP_NAME'")) | .spec')"
            if [[ "$CSTOR_BACKUP_STATUS" == "Done" ]];
            then
                verbose && printf "${GREEN}${TICK}%-10s %-75s %-10s\033[0m\n" " [OK]" "$CSTOR_BACKUP_NAME" "$CSTOR_BACKUP_STATUS" \
                && echo "$CSTOR_SPEC" | indent 12
            else
                printf "${GREEN}${TICK}%-10s %-75s %-10s\033[0m\n" " [OK]" "$CSTOR_BACKUP_NAME" "$CSTOR_BACKUP_STATUS"
                verbose && echo "$CSTOR_SPEC" | indent 12
                COUNT=$((COUNT+1))
            fi
        done <<< "$CSTOR_BACKUP_LIST"
    fi
    message cstorbackups
}

main() {
    [ "$KUBECONFIG" == "" ] && echo "Please set KUBECONFIG for the cluster." && exit
    [ -x jq ] && echo "Command 'jq' not found. Please install it." >&2 && exit 1
    check_namespace
    clear
    echo "-------------------------------------------------------------"
    echo -e "\033[0;32mCrawling objects in namespace $NAMESPACE:\033[0m"
    echo "-------------------------------------------------------------"
    if [[ "$NAMESPACE" == "openebs" ]];
    then
        OPENEBS_JSON="$(kubectl get pods -o json -n openebs)"
        POD_DETAIL="$(kubectl get po -n openebs -o wide)"
        openebs_control_plane
        openebs_data_plane
        verbose && openebs_sp && openebs_spc
        openebs_sc
        openebs_csp
        openebs_cv
        openebs_cvr
        if verbose;
        then
            cstorbackups
            openebs_blockdevices
            openebs_blockdeviceclaims
            rs
            pods
        fi
    elif [[ "$NAMESPACE" == "velero" ]];
    then
        rs
        pods
        velero_backup
        peristent_storage
    else
        rs
        pods
        peristent_storage
        verbose && ns_quota
    fi
    ! verbose && echo "Run script  with '-v' flag to get more details.."
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo "Total time taken:" "$EXECUTION_TIME"s