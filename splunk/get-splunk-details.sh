#!/bin/bash
kubeconfig_inventory="/workdir/k8sconfig/ct"

while read -r line;
do
    kubeconfig="$(echo "$line"  | awk -F ".mckinsey.cloud" '{print $1}')"
    
    splunk_index="$(kubectl get ds -n kube-system splunk-logging-fluentd -o json --kubeconfig="${kubeconfig_inventory}/${kubeconfig}.yaml" | jq -r '.spec.template.spec.containers[].env[] | select(.name=="SPLUNK_CLUSTER_INDEX") | .value')"
    
    echo "$line" | grep -i prod
	if [[ "$?" -eq 0 ]];
	then
		token="$(vault read -field=token mckube-prod/${line}/splunk-token)"
	else
		token="$(vault read -field=token mckube-npn/${line}/splunk-token)"
	fi

    echo "$line" "$splunk_index" "$token" >> out

done < json