#!/bin/bash

START_TIME=$(date +%s)
RED='\033[1;31m'
GREEN='\033[0;32m'
END='\033[0m' # No Color

usage () {
    [[ -z "$KUBECONFIG" ]] && printf "${RED}[WARNING]: Export KUBECONFIG before running the script.${END}"
    echo
    echo "export KUBECONFIG=<path_to_kubeconfig>"
    echo
    echo "./usage.sh -h                             help"
    echo "./usage.sh -n <namespace_name>            reports resource usage"
    echo
    exit
}

time_stamp=$(date +%Y%m%d_%H%M%S)
default_file_name="report_$time_stamp.csv"
dir='reports'
[[ ! -e $dir ]] && mkdir -p $dir

pod_resource_allocation () {
    if [[ ! -z "$NAMESPACE" ]];
    then
        echo "Fetching resource allocation for namespace $NAMESPACE"
        pod_resource_allocation="$(kubectl get po -n "$NAMESPACE" -o json | jq -rj '.items[] | .metadata.name, "|", .metadata.namespace,  "|", .spec.containers[].resources.limits.cpu, "|", .spec.containers[].resources.limits.memory, "|", .spec.containers[].resources.requests.cpu, "|", .spec.containers[].resources.requests.memory, "\n"')"
    else
        echo "Fetching resource allocation for all namespaces"
        pod_resource_allocation="$(kubectl get po -A -o json | jq -rj '.items[] | .metadata.name, "|", .metadata.namespace,  "|", .spec.containers[].resources.limits.cpu, "|", .spec.containers[].resources.limits.memory, "|", .spec.containers[].resources.requests.cpu, "|", .spec.containers[].resources.requests.memory, "\n"')"
    fi
    # printf "%-70s %-35s %-10s %-10s %-10s %-10s\n", 'POD_NAME' 'NAMESPACE' 'CPU_LIMITS' 'MEM_LIMITS' 'CPU_REQUESTS' 'MEM_REQUESTS'  
    # echo "$pod_resource_allocation" | awk -F '|' '{printf "%-70s %-35s %-10s %-10s %-10s %-10s\n", $1, $2, $3, $4, $5, $6}' 

    if [[ ! -z "$pod_resource_allocation" ]];
    then
        pod_resource_allocation_out_file_name="$dir/pod_resource_allocation_$default_file_name"
        echo "Fetched resource allocations for pods in namespace $NAMESPACE and storing in file $pod_resource_allocation_out_file_name"
        header=$(paste -d, <(echo "POD_NAME") <(echo "NAMESPACE") <(echo "CPU_LIMITS") \
                <(echo "MEM_LIMITS") <(echo "CPU_REQUESTS") <(echo "MEM_REQUESTS"))
        echo "$header" >> "$pod_resource_allocation_out_file_name"    
        while read -r line;
        do
            pod_name=$(echo "$line" | awk -F '|' '{print $1}')
            namespace=$(echo "$line" | awk -F '|' '{print $2}')
            cpu_limits=$(echo "$line" | awk -F '|' '{print $3}')
            mem_limits=$(echo "$line" | awk -F '|' '{print $4}')
            cpu_requests=$(echo "$line" | awk -F '|' '{print $5}')
            mem_requests=$(echo "$line" | awk -F '|' '{print $6}')
            var="$(paste -d, <(echo "$pod_name") <(echo "$namespace") \
            <(echo "$cpu_limits") <(echo "$mem_limits") <(echo "$cpu_requests") <(echo "$mem_requests"))"
            echo "$var" >> "$pod_resource_allocation_out_file_name"

        done <<< "$pod_resource_allocation"
    else
        echo "Failed fetching resource allocations for pods in namespace $NAMESPACE."
    fi
}

node_usage_details () {
    echo "Fetching resource usage for nodes"
    node_usage_details="$(kubectl top nodes)"

    if [[ ! -z "$node_usage_details" ]];
    then
        node_uasge_out_file_name="$dir/node_usage_$default_file_name"
        echo "Fetched resource usage for nodes and storing in file $node_uasge_out_file_name"
        while read -r line;
        do
            node_name=$(echo "$line" | awk '{print $1}')
            cpu_usage=$(echo "$line" | awk '{print $2}')
            cpu_percentage_usage=$(echo "$line" | awk '{print $3}')
            mem_usage=$(echo "$line" | awk '{print $4}')
            mem_percentage_usage=$(echo "$line" | awk '{print $5}') 
            var="$(paste -d, <(echo "$node_name") <(echo "$cpu_usage") \
                    <(echo "$cpu_percentage_usage") <(echo "$mem_usage") \
                    <(echo "$mem_percentage_usage"))"
            echo "$var" >> "$node_uasge_out_file_name"
        done <<< "$node_usage_details"
    else
        printf "${RED}}Failed fetching resource usage for nodes.${END}"
    fi
}


pod_usage_details () {
    if [[ ! -z "$NAMESPACE" ]];
    then
        echo "Fetching resource usage for pods in namespace $NAMESPACE"
        pod_usage_details="$(kubectl top pods -n $NAMESPACE)"
    else
        echo "Fetching resource usage for pods in all namespaces"
        pod_usage_details="$(kubectl top pods -A)"
    fi

    if [[ ! -z "$pod_usage_details" ]];
    then
        pod_usage_out_file_name="$dir/pod_resource_usage_$default_file_name"
        echo "Fetched resource usage for pods in $NAMESPACE namespace and storing in file $pod_usage_out_file_name"
        while read -r line;
        do
            if [[ ! -z "$NAMESPACE" ]];
            then
                pod_name=$(echo "$line" | awk '{print $1}')
                cpu_usage=$(echo "$line" | awk '{print $2}')            
                mem_usage=$(echo "$line" | awk '{print $3}')
                var="$(paste -d, <(echo "$pod_name") <(echo "$cpu_usage") <(echo "$mem_usage"))"
            else
                namespace=$(echo "$line" | awk '{print $1}')
                pod_name=$(echo "$line" | awk '{print $2}')
                cpu_usage=$(echo "$line" | awk '{print $3}')
                mem_usage=$(echo "$line" | awk '{print $4}')
                var="$(paste -d, <(echo "$namespace") <(echo "$pod_name") <(echo "$cpu_usage") <(echo "$mem_usage"))"
            fi
            echo "$var" >> "$pod_usage_out_file_name"
        done <<< "$pod_usage_details"
    else
        echo "${END}Failed fetching resource usage for pods in namespace $NAMESPACE.${END}"
    fi
    unset $NAMESPACE
}

main () {
    echo "Found KUBECONFIG at $KUBECONFIG"
    pod_resource_allocation
    node_usage_details
    pod_usage_details
}

OPTIND=1

while getopts "h?n:f:" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
    n)  NAMESPACE=${OPTARG}
        ;;
    esac
done
shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

[[ -z "$KUBECONFIG" ]] && echo "${RED}[ERROR] Missing mandatory requirements${END}" && usage 
[ -x jq ] && echo -e "${RED}Command 'jq' not found. Please install it.${END}" >&2 && exit 1

main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
printf "Total time taken: ${GREEN}${EXECUTION_TIME}s${END}\n"