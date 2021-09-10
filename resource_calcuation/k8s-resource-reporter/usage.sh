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

# converts cpu/mem to similar units
covert_unit_val() {
    val=$1
    val_num=$(echo $val | sed 's/[^0-9]*//g')
    [[ "$2" == "lim_cpu" ]] && cpu_limits=$(echo $val_num/1000|bc -l)
    [[ "$2" == "req_cpu" ]] && cpu_requests=$(echo $val_num/1000|bc -l)
    [[ "$2" == "pod_cpu" ]] && cpu_usage=$(echo $val_num/1000|bc -l)
    [[ "$2" == "node_cpu" ]] && cpu_usage=$(echo $val_num/1000|bc -l)
    [[ "$2" == "lim_mem_gi" ]] && mem_limits="$(($val_num*1000))Mi"
    [[ "$2" == "req_mem_gi" ]] && mem_requests="$(($val_num*1000))Mi"
    [[ "$2" == "lim_mem_ki" ]] && mem_limits="$(echo $val_num/1000|bc -l)Mi"
    [[ "$2" == "req_mem_ki" ]] && mem_requests="$(echo $val_num/1000|bc -l)Mi"
    [[ "$2" == "lim_mem_M" ]] && mem_limits="$(echo $val_num)Mi"
    [[ "$2" == "req_mem_M" ]] && mem_requests="$(echo $val_num)Mi"
    [[ "$2" == "lim_mem_byte" ]] && mem_limits="$(echo $val_num/1000000|bc -l)Mi"
    [[ "$2" == "req_mem_byte" ]] && mem_requests="$(echo $val_num/1000000|bc -l)Mi"
}

# calculates pod resource allocation
pod_resource_allocation () {
    if [[ ! -z "$NAMESPACE" ]];
    then
        echo "Fetching resource allocation for namespace $NAMESPACE"
        pod_resource_allocation="$(kubectl get po -n "$NAMESPACE" -o=jsonpath='{range .items[*]}{"\n"}{"pod_name:"}{.metadata.name}{" | pod_ns:"}{.metadata.namespace}{" | cont_name:"}{range .spec.containers[*]}{.name}{" | cont_lim_cpu:"}{..resources.limits.cpu}{" | cont_lim_mem:"}{.resources.limits.memory}{" | cont_req_cpu:"}{.resources.requests.cpu}{" | cont_req_mem:"}{.resources.requests.memory}{"\n"}{end}{end}')"
    else
        echo "Fetching resource allocation for all namespaces"
        pod_resource_allocation="$(kubectl get pods -A -o=jsonpath='{range .items[*]}{"\n"}{"pod_name:"}{.metadata.name}{" | pod_ns:"}{.metadata.namespace}{" | cont_name:"}{range .spec.containers[*]}{.name}{" | cont_lim_cpu:"}{..resources.limits.cpu}{" | cont_lim_mem:"}{.resources.limits.memory}{" | cont_req_cpu:"}{.resources.requests.cpu}{" | cont_req_mem:"}{.resources.requests.memory}{"\n"}{end}{end}')"
    fi

    if [[ ! -z "$pod_resource_allocation" ]];
    then
        pod_resource_allocation_out_file_name="$dir/pod_resource_allocation_$default_file_name"
        echo "Fetched resource allocations for pods in namespace $NAMESPACE and storing in file $pod_resource_allocation_out_file_name"
        header=$(paste -d, <(echo "POD_NAME") <(echo "NAMESPACE") <(echo "CONTAINER_NAME") <(echo "CPU_LIMITS") \
                <(echo "MEM_LIMITS") <(echo "CPU_REQUESTS") <(echo "MEM_REQUESTS"))
        echo "$header" >> "$pod_resource_allocation_out_file_name"    
        while read -r line;
        do
            if echo "$line" | grep 'pod_name' > /dev/null;
            then
                pod_name=$(echo "$line" | awk -F '|' '{print $1}' | awk -F ':' '{print $2}')
                namespace=$(echo "$line" | awk -F '|' '{print $2}' | awk -F ':' '{print $2}')
                container_name=$(echo "$line" | awk -F '|' '{print $3}' | awk -F ':' '{print $2}')
                cpu_limits=$(echo "$line" | awk -F '|' '{print $4}' | awk -F ':' '{print $2}')
                mem_limits=$(echo "$line" | awk -F '|' '{print $5}' | awk -F ':' '{print $2}')
                cpu_requests=$(echo "$line" | awk -F '|' '{print $6}' | awk -F ':' '{print $2}')
                mem_requests=$(echo "$line" | awk -F '|' '{print $7}' | awk -F ':' '{print $2}')                                
            else
                pod_name="$prev_pod_name"
                namespace="$prev_namespace"
                container_name=$(echo "$line" | awk -F '|' '{print $1}')
                cpu_limits=$(echo "$line" | awk -F '|' '{print $2}' | awk -F ':' '{print $2}')
                mem_limits=$(echo "$line" | awk -F '|' '{print $3}' | awk -F ':' '{print $2}')
                cpu_requests=$(echo "$line" | awk -F '|' '{print $4}' | awk -F ':' '{print $2}')
                mem_requests=$(echo "$line" | awk -F '|' '{print $5}' | awk -F ':' '{print $2}')
            fi

            # converting milliseconds cpu 
            [[ "$cpu_limits" =~ "m" ]] && covert_unit_val $cpu_limits 'lim_cpu'
            [[ "$cpu_requests" =~ "m" ]] && covert_unit_val $cpu_requests 'req_cpu' 

            # converting mem from Gb to Mb
            [[ "$mem_limits" =~ "G" ]] && covert_unit_val "$mem_limits" 'lim_mem_gi'
            [[ "$mem_requests" =~ "G" ]] && covert_unit_val "$mem_requests" 'req_mem_gi'

            # converting mem Kb to Mb
            [[ "$mem_limits" =~ "K" || "$mem_limits" =~ "k" ]] && covert_unit_val "$mem_limits" 'lim_mem_ki'
            [[ "$mem_requests" =~ "K" || "$mem_requests" =~ "k" ]] && covert_unit_val "$mem_requests" 'req_mem_ki'

            # converting M to Mi
            [[ "$mem_limits" =~ "M" ]] && covert_unit_val "$mem_limits" 'lim_mem_M'
            [[ "$mem_requests" =~ "M" ]] && covert_unit_val "$mem_requests" 'req_mem_M'

            # converting byte to Mi
            [[ "$mem_limits" =~ [^A-Za-z] ]] && covert_unit_val "$mem_limits" 'lim_mem_byte'
            [[ "$mem_requests" =~ =~ [^A-Za-z] ]] && covert_unit_val "$mem_requests" 'req_mem_byte'

            # creating values line to be pasted in csv
            var="$(paste -d, <(echo "$pod_name") <(echo "$namespace") <(echo "$container_name")\
            <(echo "$cpu_limits") <(echo "$mem_limits") <(echo "$cpu_requests") <(echo "$mem_requests"))"

            # appending values in csv file
            if [[ ! -z "$container_name" ]];
            then
                echo "$var" >> "$pod_resource_allocation_out_file_name"
            fi

            # retaining pod names for pods having multiple containers
            prev_pod_name="$pod_name"
            prev_namespace="$namespace"
        done <<< "$pod_resource_allocation"
    else
        printf "${RED}Failed fetching resource allocations for pods in namespace $NAMESPACE.${END}"
    fi
}

# fetching node resource usage details
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

            [[ "$cpu_usage" =~ "m" ]] && covert_unit_val $cpu_usage 'node_cpu'

            # preparing data to write in a csv file 
            var="$(paste -d, <(echo "$node_name") <(echo "$cpu_usage") \
                    <(echo "$cpu_percentage_usage") <(echo "$mem_usage") \
                    <(echo "$mem_percentage_usage"))"
            echo "$var" >> "$node_uasge_out_file_name"
        done <<< "$node_usage_details"
    else
        printf "${RED}}Failed fetching resource usage for nodes.${END}"
    fi
}

# getting pod metrics detail
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
        total_pod_cpu_usage=0
        while read -r line;
        do
            if [[ ! -z "$NAMESPACE" ]];
            then
                pod_name=$(echo "$line" | awk '{print $1}')
                cpu_usage=$(echo "$line" | awk '{print $2}')            
                mem_usage=$(echo "$line" | awk '{print $3}')
                [[ "$cpu_usage" =~ "m" ]] && covert_unit_val $cpu_usage 'pod_cpu'
                var="$(paste -d, <(echo "$pod_name") <(echo "$cpu_usage") <(echo "$mem_usage"))"
            else
                namespace=$(echo "$line" | awk '{print $1}')
                pod_name=$(echo "$line" | awk '{print $2}')
                cpu_usage=$(echo "$line" | awk '{print $3}')
                mem_usage=$(echo "$line" | awk '{print $4}')
                [[ "$cpu_usage" =~ "m" ]] && covert_unit_val $cpu_usage 'pod_cpu'
                var="$(paste -d, <(echo "$namespace") <(echo "$pod_name") <(echo "$cpu_usage") <(echo "$mem_usage"))"
            fi
            
            # writing data to the csv out file
            echo "$var" >> "$pod_usage_out_file_name"
        done <<< "$pod_usage_details"
        echo $total_pod_cpu_usage

    else
        printf "${END}Failed fetching resource usage for pods in namespace $NAMESPACE.${END}"
    fi
    unset $NAMESPACE
}

main () {
    echo "Found KUBECONFIG at $KUBECONFIG"

    # settting the value to report directory
    if [[ -z "$CUST_DIR" ]];
    then
        dir='reports'
    else
        dir="reports/$CUST_DIR"
    fi

    # creating reports dir if not found
    [[ ! -e $dir ]] && mkdir -p $dir

    # calling dedicated functions for pod and nodes
    pod_resource_allocation
    node_usage_details
    pod_usage_details
}

# getting optional arguments
OPTIND=1
while getopts "h?n:d:" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
    n)  NAMESPACE=${OPTARG}
        ;;
    d) CUST_DIR=${OPTARG}
        ;;
    esac
done
shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

[[ -z "$KUBECONFIG" ]] && echo "${RED}[ERROR] Missing mandatory requirements${END}" && usage

main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
printf "Total time taken: ${GREEN}${EXECUTION_TIME}s${END}\n"