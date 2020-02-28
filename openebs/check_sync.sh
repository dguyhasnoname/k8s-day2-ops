#!/bin/bash -e

usage() {
    [[ -z "$KUBECONFIG" ]] && echo "[WARNING]: Export KUBECONFIG before running the script."
    echo "Usage: "
    echo "./check_sync.sh -h/-help/--h      help"
    echo "./check_sync.sh                   checks replica sync status for Jiva replica pods"
    exit
}

separator() {
    echo "------------------------------------------------------"
}

check_replica_logs() {
    echo "Fetching pods in OpenEBS namespace..."
    pod_json="$(kubectl get po -n openebs -o json)"
    jiva_replica_pods="$(echo $pod_json | jq -r '.items[].metadata | select(.labels."openebs.io\/replica" == "jiva-replica") | .name')"
    apiserver_name="$(echo $pod_json | jq -r '.items[].metadata | select(.labels."openebs.io\/component-name" == "maya-apiserver") | .name')"
    replica_1="$(echo "$jiva_replica_pods" | awk '{print $1}')"

    echo "Fetching jiva volume name in OpenEBS namespace..."
    volume_name="$(echo $replica_1 | awk -F '-rep' '{print $1}')"
    separator
    echo "Fetching volume stats in OpenEBS namespace for jiva volume $volume_name..."
    volume_stats="$(kubectl exec -it $apiserver_name -n openebs -- mayactl volume describe --volname "$volume_name")"
    separator
    echo "Fetching any WO replica in OpenEBS namespace for volume $volume_name..."
    WO_replica="$(echo "$volume_stats" | grep WO | awk '{print $1}')"
    separator
    if [[ "$WO_replica" != "" ]];
    then
        echo "$volume_stats"
        echo "WO replica $WO_replica found in OpenEBS namespace for volume $volume_name. Checking logs for WO replica..."
        WO_replica_logs="$(kubectl logs $WO_replica -n openebs)"
        #WO_replica_logs="$(cat sync.log)"

        rebuild_source_ip="$(echo "$WO_replica_logs" | grep  "source for rebuild" | awk '{print $5}' | awk -F '//' '{print $2}' | awk -F ':' '{print $1}')"
        rebuild_target_ip="$(echo "$WO_replica_logs" | grep  "target for rebuild" | awk '{print $5}' | awk -F '//' '{print $2}' | awk -F ':' '{print $1}')"

        rebuild_source_pod="$(echo "$volume_stats" | grep "$rebuild_source_ip")"
        echo " "
        echo "$WO_replica is syncing data from $rebuild_source_pod"
    else
        separator
        echo "No WO replica $WO_replica found in OpenEBS namespace for volume $volume_name."
        echo "ALL JIVA REPLICAS OK!"
        separator
        echo "$volume_stats"
    fi
}

[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" || "$1" == "--help"  ]] && usage
check_replica_logs