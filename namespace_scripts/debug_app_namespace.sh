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

separator () {
    printf '\n'
}

indent () {
    x="$1"
    awk '{printf "%"'$x'"s%s\n", "", $0}'
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
        echo -e "\033[1;32m\xE2\x9C\x94           \033[0m"no issues found for "$OBJECT".
    else
        echo -e "\033[1;31;5m[ALERT!]    \033[0m"issues found for "$OBJECT"!
    fi
    separator
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
    COUNT=0
    csp_stats () {
        kubectl get csp -o json | jq -r '.items[] | select(.metadata.name | contains("'$CSP_NAME'")) | .metadata.labels."kubernetes.io\/hostname", .status.capacity' | indent 22
    }
    CSP_LIST="$(kubectl get csp -o json | jq -r '.items[].metadata.name')"
    if [[ "$CSP_LIST" != "" ]];
    then
        [ "$NAMESPACE" != "openebs" ] && echo -e "\033[0;32mcStor configuration found for namespace $NAMESPACE..\033[0m"
        while read -r line;
        do
            CSP_NAME="$line"
            CSP_STATUS="$(kubectl get csp -o json | jq -r '.items[] | select(.metadata.name | contains("'$CSP_NAME'")) | .status.phase')"
            if [[ "$CSP_STATUS" != "Healthy" ]];
            then
                echo -e "\033[1;33m! [WARNING] csp_check\033[0m" "$CSP_NAME $CSP_STATUS"
                verbose && csp_stats
                COUNT=$((COUNT+1))
            else
                echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorPool\033[0m" "$CSP_NAME $CSP_STATUS"
                verbose && csp_stats
            fi
        done <<< "$CSP_LIST"
        message cStorPool
    fi
}

cstorvolume_check () {
    replica_check () {
        [[ "$NAMESPACE" != "openebs" ]] && echo "$CV_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$PV_NAME'")) | "Specs:", .spec, "Replica status:", .status.replicaStatuses[]' | indent 24 \
        || echo "$CV_STATUS_JSON"| jq -r '.items[] | select(.metadata.name | contains("'$CV_NAME'")) | "Specs:", .spec, "Replica status:", .status.replicaStatuses[]' | indent 24
    }
    if [[ "$NAMESPACE" != "openebs" ]];
    then
        CV_STATUS="$(echo "$CV_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$PV_NAME'")) | .status.phase' )"
    else
        CV_STATUS="$(echo "$CV_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CV_NAME'")) | .status.phase' )"
    fi
    if [[ "$CV_STATUS" != "Healthy" ]];
    then
        echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]    CStorVolume\033[0m" "$CV_NAME" "$CV_STATUS"
        verbose && replica_check
        COUNT=$((COUNT+1))
    elif [[ "$CV_STATUS" == "Offline" ]];
    then
        echo -e "\033[1;33m! [WARNING]  CStorVolume\033[0m" "$CV_NAME" "$CV_STATUS"
        verbose && replica_check
        COUNT=$((COUNT+1))
    else
        echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorVolume\033[0m" "$CV_NAME" "$CV_STATUS"
        verbose && replica_check
    fi
}

cvr_check () {
    COUNT=0
    cvr_status_detail () {
        echo "$CVR_STATUS_JSON"| jq -r '.items[] | select(.metadata.name | contains("'$CVR_NAME'")) | .status' | indent 31
    }
    CVR_STATUS="$(echo "$CVR_STATUS_JSON" | jq -r '.items[] | select(.metadata.name | contains("'$CVR_NAME'")) | .status.phase')"
    if [[ "$CVR_STATUS" != "Healthy" ]];
    then
        echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]    CStorVolumeReplica\033[0m" "$CVR_NAME" "$CVR_STATUS"
        verbose && cvr_status_detail
        COUNT=$((COUNT+1))
    elif [[ "$CVR_STATUS" == "Offline" ]];
    then
        echo -e "\033[1;33m! [WARNING] CStorVolumeReplica\033[0m" "$CVR_NAME" "$CVR_STATUS"
        verbose && cvr_status_detail
        COUNT=$((COUNT+1))
    else
        echo -e "\033[1;32m\xE2\x9C\x94 [OK]      CstorVolumeReplica\033[0m" "$CVR_NAME" "$CVR_STATUS"
        verbose && cvr_status_detail
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
            PVC_STATUS="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json | jq -r '.status.phase')"
            PVC_ACCESSMODE="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json | jq -r '.status.accessModes[]')"
            echo -e "\033[0;32mPVC $PVC_NAME: $PVC_STATUS\033[0m" "$PVC_ACCESSMODE"
            pvc_check

            NAMESPACE_PV_LIST="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json | jq -r '.spec.volumeName')"
            separator
            #looping over pv
            while read -r line;
            do
                PV_NAME="$line"
                PV_STATUS="$(kubectl get pv "$PV_NAME" -o json | jq -r '.status.phase')"
                echo -e "\033[0;32mPV $PV_NAME: $PV_STATUS\033[0m" | indent 6
                COUNT=0
                pv_check | indent 6

                NS_CV_LIST="$(kubectl get cstorvolumes -A -o json | jq -r '.items[].metadata.name | select(. | contains("'$PV_NAME'"))')"
                if [ "$NS_CV_LIST" != "" ];
                then
                    separator
                    csp_check | indent 12
                    separator
                    echo -e "\033[0;32mcStorVolume status for namespace $NAMESPACE:\033[0m" | indent 12
                    COUNT=0
                    CV_STATUS_JSON="$(kubectl get cstorvolume -A -o json)"
                    while read -r line;
                    do
                        CV_NAME="$line"
                        cstorvolume_check | indent 12
                    done <<< "$NS_CV_LIST"
                    message cStorVolume | indent 12
                fi

                NS_CVR_LIST="$(kubectl get cvr -A -o json | jq -r '.items[] | select(.metadata.labels."cstorvolume.openebs.io\/name" | contains("'$PV_NAME'")) | .metadata.name')"
                if [ "$NS_CVR_LIST" != "" ];
                then
                    separator
                    echo -e "\033[0;32mcStorVolumeReplica status for namespace $NAMESPACE:\033[0m" | indent 12
                    COUNT=0
                    CVR_STATUS_JSON="$(kubectl get cvr -A -o json)"
                    while read -r line;
                    do
                        CVR_NAME="$line"
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
            echo "$CONTAINER_JSON" | awk '{printf "\033[1;31m%-10s\033[0m %-5s %-25s %-25s\n", $1, $2, $3, $4}' | indent 16
            separator
            get_event () {
                LOGS="$(kubectl logs --tail=100 "$POD_NAME" -c "$line" --previous -n "$NAMESPACE"  |  grep -i  "warn\|error\|exception\|timeout|\retry\|unexpected\|denied\|IOException" | tail -3)"
                if [ "$LOGS" != "" ];
                then
                    echo -e "\033[0;32mLogs for previous restarted container $line:\033[0m" | indent 16
                    echo -e "\033[0;31m$LOGS\033[0m" | fold -w 70 -s| indent 16
                else
                    echo -e "\033[0;32mNo issues found in logs of container $line. Check the exit code.\033[0m" | indent 16
                fi
            }
            verbose && get_event
            COUNT=$((COUNT+1))
        else
            echo -e "Container \033[1;33m$line\033[0m restart count: $RESTART" | indent 16
            echo -e "Container $line was last terminated with exitCode: \033[0;32m0\033[0m and reason: \033[0;32mCompleted\033[0m " | indent 16
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
        echo -e "\033[1;32m\xE2\x9C\x94           pods found:$POD_COUNT\033[0m"
    fi
    while read -r line;
    do
        STATUS="$(echo "$line" | awk '{print $3}')"
        POD_NAME="$(echo "$line" | awk '{print $1}')"
        POD_AGE="$(echo "$line" | awk '{print $5}')"
        POD_NODE="$(echo "$line" | awk '{print $7}')"
        RESTART="$(echo "$line" | awk '{print $4}')"

        call_pod_fun () {
            if [[ "$STATUS" == "$1" ]];
            then
                echo -e "\033[1;31m\xE2\x9D\x8C[ERROR]   pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
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

        if [[ "$STATUS" == "Completed" ]];
        then
            verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pod\033[0m" "$POD_NODE"/"$POD_NAME" status: "$STATUS"
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
                    with all containers not in running state. "\033[0;33mIt may take some time for all containers to come up.\033[0m"
                    separator
                    echo "Events in the name space $NAMESPACE:" | indent 12
                    EVENTS="$(kubectl get events -o json -n "$NAMESPACE" --field-selector type!=Normal | jq '.items[].message')"
                    echo -e "\033[0;31m$EVENTS\033[0m" | fold -w 70 -s | indent 12
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
}

velero_backup () {
    separator
    VELERO_BACKUP_JSON="$(velero backup get -o json)"
    VELERO_BACKUP_LIST="$(echo "$VELERO_BACKUP_JSON" | jq -r '.items[].metadata.name')"
    if [[ "$VELERO_BACKUP_LIST" != "" ]];
    then
        echo -e "\033[1;35mVelero backups details: \033[0m"
        separator
        echo -e "\033[1;32m\xE2\x9C\x94           velero backups found: \033[0m" "$(echo "$VELERO_BACKUP_LIST" | wc -l)"
        while read -r line;
        do
            VELERO_BACKUP_STATUS="$(echo "$VELERO_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name == "'$line'") | .status.phase')"
            VELERO_BACKUP_NAMESPACE="$(echo "$VELERO_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name == "'$line'") | .spec.includedNamespaces[]')"
            if [[ "$VELERO_BACKUP_STATUS" != "Completed" ]];
            then
                echo -e "\033[1;33m! [WARNING] backup\033[0m" "$line" status: "\033[1;31m$VELERO_BACKUP_STATUS\033[0m" for namespace "$VELERO_BACKUP_NAMESPACE"
                echo "$VELERO_BACKUP_JSON" | jq -r '.items[] | select(.metadata.name == "'$line'") | .status' | indent 16
            else
                verbose && echo -e "\033[1;32m\xE2\x9C\x94 [OK]      backup\033[0m" "$line" status: "\033[1;32m$VELERO_BACKUP_STATUS\033[0m" for namespace "$VELERO_BACKUP_NAMESPACE"
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
            echo -e "\033[0;32mPV:\033[0m" "$COMPONENT_POD_PV" | indent 24
            echo -e "\033[0;32mPVC:\033[0m" "$COMPONENT_POD_PVC" | indent 24
            echo -e "\033[0;32mStorage class:\033[0m" "$COMPONENT_POD_STORAGE_CLASS" | indent 12 | indent 12
        fi
    }
    TYPE="$1"
    while read -r line;
    do
        COMPONENT_POD_NAME="$line"
        COMPONENT_POD_STATUS="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .status.phase')"
        COMPONENT_POD_NODE="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .spec.nodeName')"
        COMPONENT_POD_CONTAINER_STATUS="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .status.containerStatuses[] | .ready')"
        COMPONENT_POD_CONTAINER_RESTART_COUNT="$(echo "$OPENEBS_JSON" | jq -rc '.items[] | select(.metadata.name=="'$COMPONENT_POD_NAME'") | .status.containerStatuses[] | .restartCount')"

        if [[ "$COMPONENT_POD_STATUS" == "Running" && ! "$COMPONENT_POD_CONTAINER_STATUS" =~ "false" && ! "$COMPONENT_POD_CONTAINER_RESTART_COUNT" =~ ^[1-9]+$ ]];
        then
            echo -e "\033[1;32m\xE2\x9C\x94 [OK]      pod\033[0m" "$line" "\033[0;32m$COMPONENT_POD_STATUS\033[0m" "$COMPONENT_POD_NODE" | indent 12
            data_plane_relation | indent 12
        else
            echo -e "\033[1;33m! [WARNING] pod\033[0m" "$line" "\033[0;32m$COMPONENT_POD_STATUS\033[0m" "$COMPONENT_POD_NODE"| indent 12
            data_plane_relation | indent 12
            COUNT=$((COUNT+1))
        fi
    done <<< "$COMPONENT_POD_LIST"
}

openebs_control_plane () {
    COUNT=0
    echo -e "\033[1;32mChecking control plane components for OpenEBS..\033[0m"
    OPENEBS_JSON="$(kubectl get pods -o json -n openebs)"
    OPENEBS_CONTROL_PLANE_LIST="$(echo "$OPENEBS_JSON" | jq -r '.items[].metadata.labels."openebs.io\/component-name"|select(.!=null)' | awk '!seen[$0]++')"
    OPENEBS_CONTROL_PLANE_PODS_TOTAL="$(echo "$OPENEBS_JSON" | jq -r '.items[].metadata.labels."openebs.io\/component-name"|select(.!=null)' | wc -l)"
    echo -e "\033[1;32m\xE2\x9C\x94           control plane components found: \033[0m" "$(echo "$OPENEBS_CONTROL_PLANE_LIST" | wc -l)" "($OPENEBS_CONTROL_PLANE_PODS_TOTAL pods)"
    separator
    while read -r line;
    do
        COMPONENT_NAME="$line"
        COMPONENT_POD_LIST="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels."openebs.io\/component-name"=="'$COMPONENT_NAME'") | .metadata.name')"
        echo -e "\033[0;35m$line:\033[0m"
        openebs_component_pod
    done <<< "$OPENEBS_CONTROL_PLANE_LIST"
    separator
}

openebs_data_plane () {
    COUNT=0
    echo -e "\033[1;32mChecking data plane components for OpenEBS..\033[0m"
    OPENEBS_JSON="$(kubectl get pods -o json -n openebs)"
    CSTOR_POOL_LIST="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels.app=="cstor-pool") | .metadata.name')"
    CSTOR_VOL_MANAGER="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels.app=="cstor-volume-manager") | .metadata.name')"
    JIVA_CONTROLLER="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels."openebs.io\/controller"=="jiva-controller") | .metadata.name')"
    JIVA_REPLICA="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels."openebs.io\/replica"=="jiva-replica") | .metadata.name')"
    NFS_PROVISIONER="$(echo "$OPENEBS_JSON" | jq -r '.items[] | select(.metadata.labels.app=="openebs-nfs-provisioner") | .metadata.name')"
    echo -e "\033[1;32m\xE2\x9C\x94           date plane components found: 5\033[0m"

    data_plane_comp_details () {
        if [[ "$1" != "" ]];
        then
            COMPONENT_NAME="$2"
            COMPONENT_POD_LIST="$1"
            echo -e "\033[0;35m$COMPONENT_NAME: $(echo "$1" | wc -l)\033[0m"
            openebs_component_pod "$3"
        else
            echo -e "\033[1;33m! [WARNING] $COMPONENT_NAME\033[0m not found."
        fi
    }

    data_plane_comp_details "$CSTOR_POOL_LIST" cstor-pool
    data_plane_comp_details "$CSTOR_VOL_MANAGER" cstor-volume-manager data
    data_plane_comp_details "$JIVA_CONTROLLER" jiva-controller
    data_plane_comp_details "$JIVA_REPLICA" jiva-replica
    data_plane_comp_details "$NFS_PROVISIONER" openebs-nfs-provisioner
    separator
}

openebs_sp () {
    separator
    OPENEBS_SP_JSON="$(kubectl get sp -o json)"
    OPENEBS_SP_LIST="$(echo "$OPENEBS_SP_JSON" | jq -r '.items[].metadata.name')"
    echo -e "\033[1;32m\xE2\x9C\x94           storage pools found:\033[0m" "$(echo "$OPENEBS_SP_LIST" | wc -l)"
    while read -r line;
    do
        OPENEBS_SP_NAME="$line"
        OPENEBS_SP_PATH="$(echo "$OPENEBS_SP_JSON" | jq -r '.items[] | select(.metadata.name=="'$OPENEBS_SP_NAME'") | .spec.path')"
        echo -e "\033[0;32m$OPENEBS_SP_NAME: \033[0m" "$OPENEBS_SP_PATH" | indent 12
    done <<< "$OPENEBS_SP_LIST"
}

openebs_spc () {
    separator
    OPENEBS_SPC_JSON="$(kubectl get spc -o json)"
    OPENEBS_SPC_LIST="$(echo "$OPENEBS_SPC_JSON" | jq -r '.items[].metadata.name')"
    echo -e "\033[1;32m\xE2\x9C\x94           storagepool claims found:\033[0m" "$(echo "$OPENEBS_SPC_LIST" | wc -l)"
    while read -r line;
    do
        OPENEBS_SPC_NAME="$line"
        OPENEBS_SPC_STATUS="$(echo "$OPENEBS_SPC_JSON" | jq -r '.items[] | select(.metadata.name=="'$OPENEBS_SPC_NAME'") | .status.phase')"
        echo -e "\033[0;32m$OPENEBS_SPC_NAME \033[0m" status: "$OPENEBS_SPC_STATUS" | indent 12
    done <<< "$OPENEBS_SPC_LIST"
}

openebs_sc () {
    separator
    OPENEBS_SC_JSON="$(kubectl get sc -o json)"
    OPENEBS_SC_LIST="$(echo "$OPENEBS_SC_JSON" | jq -r '.items[].metadata.name')"
    echo -e "\033[1;32m\xE2\x9C\x94           storage-class found:\033[0m" "$(echo "$OPENEBS_SC_LIST" | wc -l)"
    while read -r line;
    do
        OPENEBS_SC_NAME="$line"
        OPENEBS_SC_PROVISIONER="$(kubectl get sc/"$OPENEBS_SC_NAME" --no-headers)"
        OPENEBSE_SC_DETAIL="$(echo "$OPENEBS_SC_JSON" | jq -rj '.items[] | select(.metadata.name=="'$OPENEBS_SC_NAME'") | "reclaimPolicy: ", .reclaimPolicy, "\n", "volumeBindingMode: ", .volumeBindingMode')"
        ! verbose && echo "$OPENEBS_SC_PROVISIONER" | indent 12
        verbose && echo -e "\033[0;32m$OPENEBS_SC_PROVISIONER\033[0m" | indent 12 && echo "$OPENEBSE_SC_DETAIL" | indent 19
    done <<< "$OPENEBS_SC_LIST"
}

openebs_csp () {
    separator
    echo -e "\033[1;32m\xE2\x9C\x94           cStorPool found: 3\033[0m"
    csp_check
}

openebs_cv () {
    separator
    echo -e "\033[1;32m\xE2\x9C\x94           cStorVolumes found: 3\033[0m"
    CV_LIST="$(kubectl get cstorvolumes -A -o json | jq -r '.items[].metadata.name')"
    CV_STATUS_JSON="$(kubectl get cstorvolumes -A -o json)"
    while read  -r line;
    do
        CV_NAME="$line"
        cstorvolume_check
    done <<< "$CV_LIST"
}
openebs_cvr () {
    separator
    CVR_LIST="$(kubectl get cvr -A -o json | jq -r '.items[] | .metadata.name')"
    echo -e "\033[1;32m\xE2\x9C\x94           cStorVolumeReplicas found:\033[0m" "$(echo "$CV_LIST" | wc -l)"
    CVR_STATUS_JSON="$(kubectl get cvr -A -o json)"
    while read  -r line;
    do
        CVR_NAME="$line"
        cvr_check
        verbose && kubectl get cvr "$CVR_NAME" -o  json | jq '.metadata.annotations."cstorpool.openebs.io\/hostname"' | indent 31
    done <<< "$CVR_LIST"
}

debug_ns() {
    [ "$KUBECONFIG" == "" ] && echo "Please set KUBECONFIG for the cluster." && exit
    [ -x jq ] && echo "Command 'jq' not found. Please install it." >&2 && exit 1
    check_namespace
    clear
    echo "-------------------------------------------------------------"
    echo -e "\033[0;32mCrawling objects in namespace $NAMESPACE:\033[0m"
    echo "-------------------------------------------------------------"
    if [[ "$NAMESPACE" == "openebs" ]];
    then
        # openebs_control_plane
        # openebs_data_plane
        # openebs_sp
        # openebs_spc
        # openebs_sc
        #openebs_csp
        openebs_cv
        #openebs_cvr
        verbose && rs && pods
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
    fi
    ! verbose && echo "Run script  with '-v' flag to get more details.."
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
debug_ns

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo Total time taken: "$EXECUTION_TIME"s