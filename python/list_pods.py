##############################################################
# Description   : This script list pods and related PVCs in  #
# a namespace and possible reasons for pod failure.          #
# Author        : Mukund                                     #
# Date          : 29 Sep 2019                                #
##############################################################

from kubernetes import client, config
from kubernetes.client.rest import ApiException
from pprint import pprint
import sys, time, os

start_time = time.time()
config.load_kube_config()
v1 = client.CoreV1Api()

def separator():
    print  ""

def usage():
    print "\033[1;33mUsage:\033[0m"
    print "\033[0;33mexport KUBECONFIG before running the script.\033[0m"
    print "\033[0;33mpython list_pods.py <namespace>\t\t: prints pod details and possible issues in a namespace.\033[0m"
    print "\033[0;33mpython list_pods.py <namespace> -v\t: prints pod details and events in namespace.\033[0m"
    sys.exit(1)

def init_container_statuses(i):
    if i.status.init_container_statuses:
        for c in i.status.init_container_statuses:
            if not c.ready:
                print("\tinit-cont status: %s" % (c.state.waiting.reason))
                print("\tinit-cont reason: %s" % (c.state.waiting.message))

def container_statuses(i):
    running_container_count=0
    total_container_count=0
    message = ''
    pod_status = []
    if i.status.phase  != 'Failed':
        for s in i.status.conditions:
            status = s.status
            pod_status.append(status)

        for c in i.status.container_statuses:
            total_container_count += 1
            if c.ready:
                running_container_count += 1
                status = 'Running'
            elif c.state.waiting:
                status = c.state.waiting.reason
                message = c.state.waiting.message
            else:
                status = 'Terminating'
                message = c.state.terminated.exit_code
    else:
        for c in i.spec.containers:
            total_container_count += 1
        status = i.status.reason
        message =  i.status.message
        rc = 0
        running_container_count = 0
        c.restart_count = 0

    return {"container_name": c.name, "tcc": total_container_count, "status": status, \
    "reason": message, "rcc": running_container_count, "rc": c.restart_count, \
    "pod_status": pod_status }

def running_pod_cont_restart_reason(i):
    if i.status.container_statuses:
        for c in i.status.container_statuses:
            if c.restart_count > 0:
                print("\tContainer\t: %s" % (c.name))
                print("\texitCode\t: %s" % (c.last_state.terminated.exit_code))
                print("\treason\t\t: %s" % (c.last_state.terminated.reason))
                print("\tstartedAt\t: %s" % (c.last_state.terminated.started_at))
                print("\tfinishedAt\t: %s" % (c.last_state.terminated.finished_at))
                separator()

def resources(i):
    for c in i.spec.containers:
        resources = c.resources.requests
        print("\tCPU/Mem requests: %s/%s" %(resources[u'cpu'], resources[u'memory']))

def pods():
    separator()
    pod_list = v1.list_namespaced_pod(namespace, watch=False)
    print "\033[1;35mListing pods in namespace: \033[0m", namespace
    separator()
    for i in pod_list.items:
        pod_name = i.metadata.name

        cont_status = container_statuses(i)
        if any('False' in t for t in cont_status['pod_status']) or cont_status['status'] == 'Evicted':
            print("\033[1;31m\xE2\x9C\x96\033[0m \033[1;30m%-65s %s/%-2s\033[0m \033[1;31m%-25s\033[0m \033[0;30m%-3s %-20s\033[0m" \
            % (i.metadata.name, cont_status['rcc'], cont_status['tcc'], cont_status['status'], \
            cont_status['rc'], i.spec.node_name))
            init_container_statuses(i)
            print("\tCotainer name\t: %s" %(cont_status['container_name']))
            print("\texitCode/reason\t: %s" %(cont_status['reason']))
            resources(i)
        else:
            print("\033[1;32m\xE2\x9C\x94\033[0m \033[1;30m%-65s %s/%-2s\033[0m \033[1;32m%-10s\033[0m \033[0;30m%-3s %-20s\033[0m" \
            % (i.metadata.name, cont_status['rcc'], cont_status['tcc'], cont_status['status'], \
            cont_status['rc'], i.spec.node_name))
            running_pod_cont_restart_reason(i)

        for p in i.spec.volumes:
            if p.persistent_volume_claim:
                print("\tPVC name\t: %-65s" % (p.persistent_volume_claim.claim_name))

def  pvc():
    separator()
    pvc_list = v1.list_namespaced_persistent_volume_claim(namespace, watch=False)
    if pvc_list.items:
        print "\033[1;35mListing PVCs in namespace: \033[0m", namespace
        separator()
        total_pvc_count = 0
        for i in pvc_list.items:
            total_pvc_count += 1
            print("%-50s %-30s %-5s %-8s %-15s" % (i.metadata.name, i.spec.volume_name, \
            i.status.capacity[u'storage'], i.status.phase, i.status.access_modes[0]))
        separator()

def namespace_events(namespace):
    ns_events = v1.list_namespaced_event(namespace)
    firstTime = []
    for e in ns_events.items:
        if e.type != 'Normal':
            if firstTime == []:
                print("\033[1;35mEvents found in namespace: \033[0m%s" % (namespace))
                separator()
                firstTime.append('Not Empty')
            print("\033[1;31m%s\033[0m\t%s" %(e.type, e.message))

def verify_namespace(namespace):
    try:
        api_response = v1.read_namespace(namespace)
    except ApiException as e:
        print("\033[1;31mNamespace was not found!\033[0m%s" % (e))
        usage()

def main():
    try:
        verbose = sys.argv[2]
    except IndexError:
        verbose = 'null'
    try:
        os.environ['KUBECONFIG']
    except KeyError:
        print "\033[0;31mKUBECONFIG not set!\033[0m"
        usage()
    if namespace == '-h'  or namespace == '--h' or namespace == '--help' or namespace == '--help':
        usage()
    else:
        verify_namespace(namespace)
    if verbose == '-v':
        pods()
        pvc()
        namespace_events(namespace)
    elif verbose == 'null':
        pods()
        pvc()
    else:
        print "\033[0;31mInvalid input!\033[0m"
        usage()
    print("\033[1;30mTotal time taken:\033[0m %ss" % (time.time() - start_time))

if __name__ == "__main__":
    try:
        namespace = sys.argv[1]
    except IndexError:
        usage()
    namespace =  sys.argv[1]
    main()