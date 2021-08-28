#!/bin/bash

###############################################################################################
# store all kubeconfigs in kubeconfig dir and run the script                                  #
# for each kubeconfig from kubeconfig dir                                                     #
# to export for specific namespace for all clusters export NAMESPACE=<namespace_name>         #
###############################################################################################

for i in $(ls -lrt kubeconfig| awk 'NR>1{print $NF}');
do
    export KUBECONFIG=kubeconfig/$i;
    ./usage.sh $i; 
done