#!/bin/bash
#######################################################################################
# Description: This script verfies any workload health during robin node maintenance  #
# Author:      Mukund                                                                 #
# Date:        8th April 2023                                                         #
# Version:     1.0.0                                                                  #
#######################################################################################


START_TIME=$(date +%s)
RED='\033[1;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1;33m'
END='\033[0m'

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
    printf "./robin-maintenance.sh -n <node_name> -k /tmp/kubeconfig \n\n"
    echo "Flags:"
    echo "  -h                  help"
    echo "  -n   Mandatory      Robin node to be set for maintenance"
    echo "  -k   Optional       kubeconfig file location"
    separator
    exit
}

pod_scheduling_status() {
    pod_name="$1"
    pod_ns="$2"
    pod_data="$3"
    echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Checking pod details for pod ${pod_name} in namespace ${pod_ns}"
    pod_owner_kind="$(echo "$pod_data" | jq -r '.metadata.ownerReferences[0].kind')"
    #pod_owner_kind="$(kubectl get pod ${pod_name} -n ${pod_ns} -o jsonpath='{.metadata.ownerReferences[0].kind}')"
    if [[ ${pod_owner_kind} == "ReplicaSet" ]];
    then
        pod_rs_name="$(echo "$pod_data" | jq -r '.metadata.ownerReferences[0].name')"
        pod_deploy_name="$(kubectl get rs ${pod_rs_name} -n ${pod_ns} -o jsonpath='{.metadata.ownerReferences[0].name}')"
        echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Pod ${pod_name} in namespace ${pod_ns} is owned by replicaset ${pod_rs_name} and deployment ${pod_deploy_name}"
        echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Waiting for Deployment ${pod_deploy_name} in namespace ${pod_ns} owned by replicaset ${pod_rs_name} to get healthy"
        kubectl wait --for condition=Available=True  deploy ${pod_deploy_name} -n ${pod_ns}
        if [[ "$?" -eq 0 ]];
        then
            echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Deployment ${pod_deploy_name} in namespace ${pod_ns} owned by replicaset ${pod_rs_name} is HEALTHY"
        fi
    elif [[ ${pod_owner_kind} == "StatefulSet" ]];
    then
        pod_sts_name="$(echo "$pod_data" | jq -r '.metadata.ownerReferences[0].name')"
        echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Pod ${pod_name} in namespace ${pod_ns} is ownded by statefulset ${pod_sts_name}"
        echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Waiting for statefulset ${pod_sts_name} in namespace ${pod_ns} to get healthy"
        kubectl wait --for condition=Available=True  sts ${pod_sts_name} -n ${pod_ns} 
        if [[ "$?" -eq 0 ]];
        then
            echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Statefulset ${pod_sts_name} in namespace ${pod_ns} is HEALTHY"
        fi
    elif [[ ${pod_owner_kind} == "DaemonSet" ]];
    then
        pod_ds_name="$(echo "$pod_data" | jq -r '.metadata.ownerReferences[0].name')"
        echo -e "${YELLOW}[WARNING]${END} `date "+%Y-%m-%d %H:%M:%S%p"` Pod ${pod_name} in namespace ${pod_ns} is ownded by daemonset ${pod_ds_name}. No need to check its status"
        # below lines are commented out as there is not need to check for daemonset
        # echo -e "${GREEN}[INFO]     ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Pod ${pod_name} in namespace ${pod_ns} is ownded by ds ${pod_ds_name}"
        # echo -e "${GREEN}[INFO]     ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Waiting for daemonset ${pod_ds_name} in namespace ${pod_ns} to get healthy"
        # kubectl wait --for condition=Available=True  ds ${pod_ds_name} -n ${pod_ns}
        # if [[ "$?" -eq 0 ]];
        # then
        #     echo -e "${GREEN}[INFO]     ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Daemonset ${pod_ds_name} in namespace ${pod_ns} is HEALTHY"
        # fi
    fi
}

upgrade_node () {
    node_check="$(kubectl get node ${NODE_NAME} -o wide)"
    if [[ "$?" -eq 0 ]];
    then
        separator
        echo "$node_check"
        separator
        echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Node found. Sending node ${NODE_NAME} in maintenance"
        
        # uncomment below line to set in maintenance mode
        #robin host set-maintenance ${NODE_NAME}"
        if [[ "$?" -eq 0 ]];
        then
            echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Finding pods running on node ${NODE_NAME}"
            pods_on_node="$(kubectl get pods --all-namespaces --no-headers -o wide --field-selector spec.nodeName=${NODE_NAME})"
            pod_count="$(echo "${pods_on_node}" | wc -l | tr -d " ")"
            separator
            echo "$pods_on_node"
            separator
            echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` ${pod_count} pods running on node ${NODE_NAME}"
            pods_on_node_json="$(kubectl get pods --all-namespaces --no-headers -o wide --field-selector spec.nodeName=${NODE_NAME} -o json)" 
                     
            if echo "$node_check" | awk '{print $2}'| grep 'SchedulingDisabled' > /dev/null;
            then
                echo -e "${YELLOW}[WARNING]${END} `date "+%Y-%m-%d %H:%M:%S%p"` Node ${NODE_NAME} already drained"
            else
                echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Draining node ${NODE_NAME}"
                separator
                timeout 900 kubectl drain $NODE_NAME  --delete-emptydir-data --force=true --ignore-daemonsets=true --disable-eviction=true
                separator
            fi
            if [[ $? -eq 0 ]];
            then
                while read -r line;
                do
                    pod_status="$(echo "${line}" | awk '{ print $4}')"
                    if [[ "${pod_status}" != "Completed" ]];
                    then
                        pod_namespace="$(echo "${line}" | awk '{ print $1}')"
                        pod_name="$(echo "${line}" | awk '{ print $2}')"
                        pod_data="$(echo "$pods_on_node_json" | jq '.items[] | select(.metadata.name=="'$pod_name'") | .')"
                        pod_scheduling_status "$pod_name" "$pod_namespace" "$pod_data"
                    fi
                done <<< "$pods_on_node"
            else
                echo -e "${GREEN}[INFO]   ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Failed to drain node ${NODE_NAME}"
            fi
        fi
        # perform the os upgrade at this point
    else
        echo -e "${RED}[ERROR]${END} `date "+%Y-%m-%d %H:%M:%S%p"` Node ${NODE_NAME} not found"
    fi    

}

main () {
    separator
    echo -e "${GREEN}[INFO]    ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Checking cluster health"
    cluster_health="$(kubectl get nodes)"
    if [[ "$?" -eq 0 ]];
    then
        separator
        echo "$cluster_health"
        separator
        echo -e "${GREEN}[INFO]    ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Cluster is reachable. Initiating maintenance"
        upgrade_node
    else
        echo -e "${RED}[ERROR] ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Cluster not reachable. Exiting immediately"
        exit
    fi
}

OPTIND=1
while getopts "h?:n:k" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
    n)  NODE_NAME=$OPTARG
        ;;    
    k)  KUBECOFNIG=$OPTARG
        ;;
    esac
done
shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

[[ -z "$NODE_NAME" ]] && echo -e "${RED}[ERROR] ${END} `date "+%Y-%m-%d %H:%M:%S%p"` Missing mandatory arguments" && usage 
[ -x kubectl ] && echo -e "${RED}[ERROR] ${END} `date "+%Y-%m-%d %H:%M:%S%p"` kubectl cli not found. Please install it." >&2 && exit 1
[ -x jq ] && echo -e "${RED}[ERROR] ${END} `date "+%Y-%m-%d %H:%M:%S%p"` jq command not found. Please install it." >&2 && exit 1

main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo "Total time taken:" "$EXECUTION_TIME"s
