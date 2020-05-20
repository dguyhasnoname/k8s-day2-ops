# k8s-day2-ops
This repository contain scripts for Kubernetes day 2 operations

## Index of scripts
1. kubelet scripts
    - kubelet_check.sh
        - This scripts checks kubelet status for all nodes in cluster.
2. k8s namespace operation scripts
    - debug_app_namespace.sh
        - This script helps debugging issues in a namespace.
    - get_namespace_objects.sh
        - This script fetches all kinds of objects present in namespace.
    - probe_namespace_errors.sh
        - This script tries to find errors across all pods in a namespace.
3. k8s pod operation scripts
    - container_exitcode.sh
        - This script finds exit codes for exited containers.
    - multiple_pod_delete.sh
        - This script can be used to delete multiple pods having a string common in their name.
    - pod_error_count.sh
4. k8s cluster resource calculation scripts
    - util.sh:  DEPRECATED
        - This script calculates resources in a cluster. 
5. k8s cluster upgrade related scripts
    - k8s-deprecations.sh
        - This script lists all apiVersion deprecations in a cluster alongwith namespace: object relation.
        - This script works for k8s version > 1.x.x

## Sample run

### debug_app_namespace.sh

![image](doc/images/debug_app_namespace)
