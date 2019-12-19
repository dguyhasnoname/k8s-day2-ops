##############################################################
# Description   : This script list pods and related PVCs in  #
# a namespace and possible reasons for pod failure.          #
# Author        : Mukund                                     #
# Date          : 29 Sep 2019                                #
##############################################################

from kubernetes import client, config
from kubernetes.client.rest import ApiException
from pprint import pprint
import sys, time, os, textwrap
import datetime, pytz

start_time = time.time()
config.load_kube_config()
v1 = client.CoreV1Api()
v2 = client.AppsV1Api()
v3 = client.ExtensionsV1beta1Api()

def separator():
    print  ""

def usage():
    print "\033[1;33mUsage:\033[0m"
    print "\033[0;33mexport KUBECONFIG before running the script.\033[0m"
    print "\033[0;33mpython list_pods.py <namespace>\t\t: prints pod details and possible issues in a namespace.\033[0m"
    print "\033[0;33mpython list_pods.py <namespace> -v\t: prints pod details and events in namespace.\033[0m"
    sys.exit(1)

def age(creation_time):
    utc_time = datetime.datetime.now(pytz.UTC)
    age = utc_time - creation_time
    def convert_timedelta(duration):
        days, seconds = duration.days, duration.seconds
        no_of_days = days
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        seconds = (seconds % 60)
        return no_of_days, hours, minutes, seconds
    no_of_days, hours, minutes, seconds = convert_timedelta(age)
    total_age = str(no_of_days) + "d" +  str(hours) + "h" + str(minutes) + "m"
    return total_age

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
            elif c.state.terminated.exit_code:
                status = 'Terminating'
                message = c.state.terminated.exit_code
            else:
                status = ''
                message = ''
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

def container_logs(i,c,namespace):
    name = i.metadata.name
    container = c.name
    namespace = namespace
    output = ''
    last_line = ''
    prev_cont_logs = ''
    error_string = [ 'error', 'fail', 'kill', 'timeout', 'denied', 'retry', \
        'unexpected', 'IOException', 'refuse', 'warn', 'exception', 'terminate' ]
    try:
        prev_cont_logs = v1.read_namespaced_pod_log(name, namespace, container=container, \
            previous=True, tail_lines=10, timestamps=True)
    except ApiException as e:
        pass

    if prev_cont_logs != '':
        print("\t\033[1;33mPrevious container logs for container:\033[0m %s" % (container))
        for line in iter(prev_cont_logs.splitlines()):
            for l in error_string:
                if l.lower() in line.lower():
                    if last_line != line:
                        print(textwrap.fill(line, 100, initial_indent=("\t"),subsequent_indent=("\t")))
                    last_line = line
    else:
        print("\t\033[1;33mNo errors found in logs of previous instance of container:\033[0m %s" % (container))


def running_pod_cont_restart_reason(i,verbose,namespace):
    if i.status.container_statuses:
        for c in i.status.container_statuses:
            if c.restart_count > 0:
                print("\tcontainer\t: %s" % (c.name))
                if c.last_state.terminated:
                    print("\texitCode\t: %s" % (c.last_state.terminated.exit_code))
                    print("\treason\t\t: %s" % (c.last_state.terminated.reason))
                    print("\tstartedAt\t: %s" % (c.last_state.terminated.started_at))
                    print("\tfinishedAt\t: %s" % (c.last_state.terminated.finished_at))
                else:
                    print("\tLast state of container was not found!\t")
                separator()
                if verbose == '-v':
                    container_logs(i,c,namespace)

def resources(i):
    for c in i.spec.containers:
        res = c.resources.requests
        if res is not None:
            #pprint(c.resources.requests)
            for key in res.keys():
                print("\t%s\t\t: %s" %(key, res[key]))

# def svc(namespace,pod_label):
#     svc_list = v1.list_namespaced_service(namespace)
#     for i in svc_list.items:
#         if u'app' in pod_label:
#             label_selector = pod_label[u'app']
#             pprint(label_selector)
#             if i.spec.selector[u'app'] == label_selector:
#                 print("\tservice name\t: %s" % (i.metadata.name))
#         else:
#             print("\tservice name\t: kube-dns, coreos-prometheus-operator-coredns" )

def ingress(ing_list,namespace,pod_label):
    if u'app' in pod_label:
        label_selector = pod_label[u'app']
    elif u'component' in pod_label:
        label_selector = pod_label[u'component']
    else:
        label_selector = pod_label[u'k8s-app']
    #pprint(label_selector)
    #ing_list = v3.list_namespaced_ingress(namespace)
    for i in ing_list.items:
        if i.metadata.labels[u'app'] == label_selector:
            for j in i.spec.rules:
                print("\tingress\t\t: %s" %(j.host))

def pods():
    separator()
    pod_list = v1.list_namespaced_pod(namespace, watch=False)
    ing_list = v3.list_namespaced_ingress(namespace)
    print "\033[1;35mListing pods in namespace: \033[0m", namespace
    separator()
    if pod_list.items:
        for i in pod_list.items:
            pod_name = i.metadata.name
            creation_time = i.metadata.creation_timestamp
            total_age = age(creation_time)
            pod_label = i.metadata.labels

            cont_status = container_statuses(i)
            if any('False' in t for t in cont_status['pod_status']) or cont_status['status'] == 'Evicted':
                print("\033[1;31m\xE2\x9C\x96\033[0m \033[1;30m%-65s %s/%-2s\033[0m \033[1;31m%-25s\033[0m %-3s %-10s %-20s" \
                % (i.metadata.name, cont_status['rcc'], cont_status['tcc'], cont_status['status'], \
                cont_status['rc'], total_age, i.spec.node_name))
                init_container_statuses(i)
                print("\tcontainer name\t: %s" %(cont_status['container_name']))
                print("\texitCode/reason\t: %s" %(cont_status['reason']))
                resources(i)
            else:
                print("\033[1;32m\xE2\x9C\x94\033[0m \033[1;30m%-65s %s/%-2s\033[0m \033[1;32m%-10s\033[0m %-3s %-10s %-20s" \
                % (i.metadata.name, cont_status['rcc'], cont_status['tcc'], cont_status['status'], \
                cont_status['rc'], total_age, i.spec.node_name))
                running_pod_cont_restart_reason(i,verbose,namespace)

            #svc(namespace,pod_label)
            ingress(ing_list,namespace,pod_label)
            for p in i.spec.volumes:
                if p.persistent_volume_claim:
                    print("\tPVC name\t: %-65s" % (p.persistent_volume_claim.claim_name))
    else:
        print "\033[1;33mNo running pods found in namespace\033[0m", namespace

def  pvc():
    separator()
    pvc_list = v1.list_namespaced_persistent_volume_claim(namespace, watch=False)
    if pvc_list.items:
        print "\033[1;35mListing PVCs in namespace: \033[0m", namespace
        separator()
        total_pvc_count = 0
        for i in pvc_list.items:
            total_pvc_count += 1
            print("%-55s %-30s %-5s %-8s %-15s" % (i.metadata.name, i.spec.volume_name, \
            i.status.capacity[u'storage'], i.status.phase, i.status.access_modes[0]))
        separator()

def replicaset(namespace):
    separator()
    rs_list  = v2.list_namespaced_replica_set(namespace)
    if rs_list.items:
        print "\033[1;35mListing replicaSets in namespace: \033[0m", namespace
        print 'NAME'.ljust(50, ' '), 'DESIRED'.ljust(7, ' '), 'CURRENT'.ljust(7, ' '), \
            'READY'.ljust(7, ' '), 'AGE'.ljust(5, ' ')
        for rs in rs_list.items:
            if rs.spec.replicas != 0:
                creation_time = rs.metadata.creation_timestamp
                total_age = age(creation_time)
                print("%-50s %-7s %-7s %-7s %-5s" %(rs.metadata.name, rs.spec.replicas, \
                rs.status.fully_labeled_replicas, rs.status.available_replicas, total_age))

def namespace_events(namespace):
    ns_events = v1.list_namespaced_event(namespace)
    firstTime = []
    last_event = ''
    for e in ns_events.items:
        if e.type != 'Normal':
            if firstTime == []:
                print("\033[1;35mEvents found in namespace which needs attention: \033[0m%s" % (namespace))
                separator()
                firstTime.append('Not Empty')
            if e.message != last_event:
                print("\033[1;31m%s\033[0m\t%s\%s\t%s" %(e.type, e.involved_object.kind, e.involved_object.name, e.message))
            last_event = e.message

def verify_namespace(namespace):
    try:
        api_response = v1.read_namespace(namespace)
        print("\033[1;32mNamespace found: \033[0m%s" %(namespace))
    except ApiException as e:
        print("\033[1;31mNamespace was not found!\033[0m%s" % (e))
        usage()

def main():
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
        replicaset(namespace)
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
        print "\033[0;31mEmpty Arguments!\033[0m"
        usage()
    try:
        verbose = sys.argv[2]
    except IndexError:
        verbose = 'null'
    namespace =  sys.argv[1]
    main()