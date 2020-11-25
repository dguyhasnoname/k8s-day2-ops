#!/bin/bash 
#######################################################################
# This script greps for case-insentitive string in a pod over         #
# the last given minutes. It can optionally & additional param like   #
# '10m' or '24h' to change the --TIME= value. Default ns is kube-     #
# system. This script needs KUBECONFIG to be exported prior to run it.#
# Author: Mukund                                                      #
# Date: 17th August 2019                                              #
# Version: 1.0                                                        #
#######################################################################

START_TIME=$(date +%s)
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BOLD='\033[1;30m'
TICK='\xE2\x9C\x94'
NOT_OK='\xE2\x9D\x8C'
END='\033[0m'

usage() {
    echo "[WARNING] It may be a invalid sytanx!"
    echo "Usage: pod_error_count.sh -p <pod_names_to_grep> -t <optional time(5m or 2h); default 5m> -n <namespace, default vaules is kube-system>  -s <optional search string>."
    echo "e.g pod_error_count.sh -p kube-proxy -t 24h -n kube-system -s invalid"
    separator
    exit
}

separator() {
    printf "\n\n"
}

pod_list(){
    separator
    echo -e "${GREEN}[RUNNING]${END} kubectl -n "$NAMESPACE" get pods --no-headers | grep -i "$POD_NAME" "
    POD_LIST="$(kubectl -n "$NAMESPACE" get pods --no-headers | grep -i "$POD_NAME" |  awk '{print $1}')"

    if [[ "$POD_LIST" == "" ]];
    then
        echo -e "${YELLOW}[WARNING]${END} Pod names with containing string \"$POD_NAME\" not found in namespace $NAMESPACE!"
        separator
        exit
    else
        echo -e "${GREEN}Pods found:${END}" 
        echo "$POD_LIST"
    fi
}

grep_error() {
    [ -z "$STRING" ] && get_count && exit
    separator
    printf "searching for string $STRING in logs for pods $POD_NAME in namespace $NAMESPACE in last $TIME..."
    pod_list
    
    while IFS= read -r line;
    do
        separator
        echo -e "${GREEN}[RUNNING]${END} kubectl -n $NAMESPACE logs $line --since=$TIME | grep -aci $STRING"
        MATCHES_COUNT=$(kubectl -n "$NAMESPACE" logs "$line" --since="$TIME" | grep -aci "$STRING")
        echo -e "${BOLD}Pod:${END} $line" 
        echo -e "${BOLD}Count${END} of matches for string \"$STRING\" in logs: ${BOLD}$MATCHES_COUNT${END}"
    done <<< "$POD_LIST"
    separator
}

OPTIND=1         

while getopts "h?n:s:p:t:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    n)  NAMESPACE=$OPTARG
        ;;   
    s)  STRING=$OPTARG 
        ;;
    p)  POD_NAME=$OPTARG
        ;;
    t)  TIME=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

[[ -z "$NAMESPACE"  || -z "$STRING" ]] && \
echo "[ERROR] Missing mandatory arguments" && usage 
[[ "$TIME" == "" ]] && TIME='5m'
[[ "$NAMESPACE" == "" ]] && NAMESPACE='kube-system'
[[ "$STRING" == "" ]] && STRING='error'

grep_error

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
echo "Total time taken:" "$EXECUTION_TIME"s