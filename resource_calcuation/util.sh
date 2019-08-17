#!/bin/bash -e
#######################################################################
# This script gives calculates resource utilisation for cluster       #
# KUBECONFIG needs to be exported as env before running the script    #
# Author: Mukund                                                      #
# Date: 17th August 2019                                              #
# Version: 1.0                                                        #
#######################################################################

clear

KUBECTL_CMD="kubectl --kubeconfig=$KUBECONFIG"

separator() {
    echo "----------------------------------------------------------"
}

separator

echo Fetching worker nodes...
$KUBECTL_CMD get nodes --no-headers | grep -v master | awk '{print $1}' > WORKER_NODES

[ $? -eq 0 ] && $KUBECTL_CMD get nodes --no-headers | grep -v master
TOTAl_CPU_REQUESTS=0
TOTAl_MEM_REQUESTS=0
TOTAl_CPU_LIMITS=0
TOTAl_MEM_LIMITS=0
TOTAL_NODE_CPU=0
TOTAL_NODE_MEM=0

separator

echo Fetching resource utilisation on above worker nodes...

while read -r line;
do
    $KUBECTL_CMD describe node $line| grep Allocated -A 5 | grep -ve Event -ve Allocated -ve percent -ve -- > ${line}_NODE_RESOURCE

    CPU_REQ=$(cat ${line}_NODE_RESOURCE | grep cpu | awk -F '[^0-9]*' '{print $2}')
    MEM_REQ=$(cat ${line}_NODE_RESOURCE | grep memory | awk -F '[^0-9]*' '{print $2}')

    CPU_LIMIT=$(cat ${line}_NODE_RESOURCE | grep cpu | awk -F '[^0-9]*' '{print $4}')
    MEM_LIMIT=$(cat ${line}_NODE_RESOURCE | grep memory | awk -F '[^0-9]*' '{print $4}')

    NODE_CPU=$($KUBECTL_CMD get node $line -o json | jq '.status.capacity.cpu' | grep -o '[0-9]\+')
    NODE_MEM=$($KUBECTL_CMD get node $line -o json | jq -r '.status.capacity.memory' | grep -o '[0-9]\+')

    TOTAl_CPU_REQUESTS=$((TOTAl_CPU_REQUESTS+CPU_REQ))
    TOTAl_MEM_REQUESTS=$((TOTAl_MEM_REQUESTS+MEM_REQ))

    TOTAl_CPU_LIMITS=$((TOTAl_CPU_LIMITS+CPU_LIMIT))
    TOTAl_MEM_LIMITS=$((TOTAl_MEM_LIMITS+MEM_LIMIT))

    TOTAL_NODE_CPU=$((TOTAL_NODE_CPU+NODE_CPU))
    TOTAL_NODE_MEM=$((TOTAL_NODE_MEM+NODE_MEM))

    separator
    echo $line resources:

    cat ${line}_NODE_RESOURCE
    rm -rf ${line}_NODE_RESOURCE
done < "WORKER_NODES"

TOTAL_NODE_MEM=$((TOTAL_NODE_MEM/1024/1024))
separator
echo TOTAl_CPU_REQUESTS in cluster=${TOTAl_CPU_REQUESTS}m
echo TOTAl_MEM_REQUESTS in cluster=${TOTAl_MEM_REQUESTS}Mi
echo TOTAl_CPU_LIMITS in cluster=${TOTAl_CPU_LIMITS}m
echo TOTAl_MEM_LIMITS in cluster=${TOTAl_MEM_LIMITS}Mi
echo TOTAL_NODE_CPU in cluster=$TOTAL_NODE_CPU
echo TOTAL_NODE_MEM in cluster=${TOTAL_NODE_MEM}Gi
separator
