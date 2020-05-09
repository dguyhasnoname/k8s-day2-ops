#!/bin/bash

KUBECONFIG_FILE="$(echo $KUBECONFIG)"

OBJECT="$1"

get_certs () {
    cacert_encoded="$(yq r  "$KUBECONFIG_FILE"  clusters.[0].cluster.certificate-authority-data)"
    apiserver_crt_encoded="$(yq r  "$KUBECONFIG_FILE"  users.[0].user.client-certificate-data)"
    apiserver_key_encoded="$(yq r  "$KUBECONFIG_FILE"  users.[0].user.client-key-data)"
    cluster_name="$(yq r  "$KUBECONFIG_FILE"  clusters.[0].cluster.server)"

    echo $cacert_encoded | base64 -d > cacert
    echo $apiserver_crt_encoded | base64 -d > apiserver_crt
    echo $apiserver_key_encoded | base64 -d > apiserver_key

}

main () {
    get_certs
    curl --cacert cacert --cert apiserver_crt --key apiserver_key ${cluster_name}/api/${OBJECT}
    rm -rf cacert apiserver_crt apiserver_key
}

main