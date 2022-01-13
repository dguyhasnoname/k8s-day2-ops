#!/bin/bash

START_TIME=$(date +%s)
YELLOW='\033[0;33m'
RED='\033[0;31m'
GREEN_BOLD='\033[1;32m'
GREEN='\033[0;32m'
BOLD='\033[1;30m'
NC='\033[0m'
TICK='\xE2\x9C\x94'

separator () {
    printf '\n'
}

indent () {
    x="$1"
    awk '{printf "%"'"$x"'"s%s\n", "", $0}'
}

usage () {
    separator
    echo "kube-releases script lists downs the k8s releases, thier patch versions, release dates and end of life date."
    separator
    echo "Usage: "
    echo "./kube-releases.sh"
    separator
    echo "Options:"
    echo "-h           help"
    echo "-v           pass version for version specific check only. e.g. -v 1.18"
    exit
}

main () {
    k8s_repo_url="https://github.com/kubernetes/kubernetes"
    all_version_url="${k8s_repo_url}/tree/master/CHANGELOG"
    end_of_life_url="https://kubernetes.io/releases/patch-releases/"
    tag_url="${k8s_repo_url}/releases/tag/"

    if [ -z "$VERSION" ]; then
        echo "[INFO] Checking k8s releases for k8s version 1.15.x and above..."
        all_version_list="$(curl -s ${all_version_url} | grep '<li><a href="/kubernetes/kubernetes/blob/master/CHANGELOG' | awk -F '"' '{print $2}' | awk -F '-' '{print $2}' | awk -F '.md' '{print $1}')"
    else
        echo "[INFO] Checking k8s release details for k8s version $VERSION.x..."
        all_version_list="$VERSION"
    fi
    [ -z "$all_version_list" ] && echo "[ERROR] No kubernetes version data found!" && exit 1
    end_of_life="$(curl -s ${end_of_life_url})"
    all_json="[]"
    while read -r line; do
        version_json=''
        if [[ "$(echo "$line" | sed -e 's/\.//g')" -lt 115 ]]; then
            echo -e "${YELLOW}[WARNING]${NC} v$line is a very old version of k8s, skipping the check."
            version_json='{"version": "unsupported version"}'
        else
            version_url="${k8s_repo_url}/blob/master/CHANGELOG/CHANGELOG-${line}.md"
            version_data="$(curl -s ${version_url})"
            version_patch_list="$(echo "$version_data" | grep kubernetes.tar.gz | awk -F '/' '{print $4}')"
            patch_count="$(echo "$version_patch_list" | wc -l | xargs)"
            end_of_life_version="$(echo "$end_of_life" | grep "End of Life" | grep "$line" | awk -F 'strong>' '{print $4}' | awk -F '<' '{print $1}')"

            if [ -z "$end_of_life_version" ]; then
                end_of_life_version="$(echo "$end_of_life" | grep -A1000 "These releases are no longer supported" | grep -A1 "$line" | tail -1 | awk -F '>' '{print $2}' | awk -F '<' '{print $1}')"
            fi

            if [ -z "$OUTPUT" ]; then
                printf "${BOLD}%-36s${NC}${RED}%-10s${NC}\n" "v${line}.x" "End of life: $end_of_life_version"
                printf "${GREEN_BOLD}%-30s%-10s${NC}" "patch_version" "release_date"| indent 6
            fi

            patch_json="[]"
            while read -r patch; do
                patch_url="${tag_url}/${patch}"
                patch_release_date="$(curl -s "$patch_url" | grep -A3 "released this" | grep 'datetime' | awk -F '"' '{print $2}' | awk -F 'T' '{print $1}')"
                _patch_json='{"patch": "'${patch}'", "release_date": "'${patch_release_date}'"}'
                patch_json=$(jq --argjson json "$(echo "$_patch_json" | jq .)" '. += [$json]' <<< ${patch_json})

                if [ "$(echo "$patch" | awk -F '.' '{print $NF}')" -eq 0 ]; then
                    version_release_date="$patch_release_date"
                fi
                [ -z "$OUTPUT" ] && printf "${GREEN}%-30s%-10s${NC}" ${patch} ${patch_release_date}| indent 6
            done <<< "$version_patch_list"

            version_json='{"version": "'${line}'", "release_date": "'${version_release_date}'", "end_of_life": "'${end_of_life_version}'", "patch_count": "'${patch_count}'", "patch_list": '${patch_json}'}'
            separator
            all_json=$(jq --argjson json "$(echo "$version_json" | jq .)" '. += [$json]' <<< ${all_json})
            if [ -z "$OUTPUT" ]; then
                echo "Total patches: $patch_count" | indent 6
                echo "--------------------------------------------------------------"
            fi
        fi
    done <<< "$all_version_list"
    [ "$OUTPUT" == "json" ] && echo "$all_json" | jq .
}

OPTIND=1

while getopts "h?v:o:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    v)  VERSION=$OPTARG
        ;;
    o) OUTPUT=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift
main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo "Total time taken:" "$EXECUTION_TIME"s