#!/bin/bash
#######################################################################################
# Description: This script find size of image being consumed by pods in a cluster     #
# Author:      Mukund                                                                 #
# Date:        19th April 2023                                                        #
# Version:     1.0.0                                                                  #
#######################################################################################

echo `date +%Y-%m-%d` "Getting all pods in cluster"
ALL_PODS_LIST="$(kubectl get pods -A -o wide --no-headers)"

while read -r pod;
do
    POD_NAME="$(echo "$pod" | awk '{print $2}')"
    POD_NAMESPACE="$(echo "$pod" | awk '{print $1}')"
    POD_IMAGES="$(kubectl get pods "$POD_NAME" -n "$POD_NAMESPACE" -o jsonpath='{range .spec.containers[*]}{.image}{", "}{end}')"
    POD_NODE_NAME="$(echo "$pod" | awk '{print $8}')"

    for i in ${POD_IMAGES//,/ }
    do
        IMAGE_NAME="$i"
        POD_IMAGE_SIZE="$(kubectl get node "$POD_NODE_NAME" -o json | jq '.status.images[] | select(.names[] | contains("'$IMAGE_NAME'"))  | .sizeBytes')"
        echo $POD_NAMESPACE $POD_NAME $POD_NODE_NAME $POD_IMAGE_SIZE
    done
done <<< "$ALL_PODS_LIST"