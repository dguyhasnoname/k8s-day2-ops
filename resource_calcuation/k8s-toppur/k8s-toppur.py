import os, getopt, argparse, sys, time, math
start_time = time.time()
import urllib3
from datetime import datetime, timezone
from modules.logging import Logger
from modules.getopts import GetOpts
from modules.get_custom_object import K8sCustomObjects
from modules.output import Output
from modules.get_ns import K8sNameSpace

def usage():
    parser=argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""This script can be used to see resource usage in kubernetes cluster.

Before running script export KUBECONFIG file as env:
    export KUBECONFIG=<kubeconfig file location>
    
    e.g. export KUBECONFIG=/Users/dguyhasnoname/kubeconfig\n""",
        epilog="""All's well that ends well.""")
    
    parser.add_argument('-s', '--sort', action="store_true", help="sort by cpu/memory. Default sorting is by name.")
    parser.add_argument('-n', '--namespace', action="store_true", help="check resources in specific namespace.")
    parser.add_argument('-f', '--filter', action="store_true", help="filter resource usage by namespace|pods.")
    parser.add_argument('-o', '--output', action="store_true", help="output formats csv|json|tree. Default is text on stdout.")
    parser.parse_args()

class K8sToppur():
    #  collects resource usage by node. Verfied o/p from kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | jq -r '.items[].usage.memory' | sed 's/[^0-9]*//g'  |  awk '{ sum += $1 } END { print sum }' 
    def get_nodes(output, sort):
        data, total_cpu, total_mem = [], 0, 0
        _logger = Logger.get_logger('K8sToppur', output)
        _logger.info("Getting node details.")
        node_details = K8sCustomObjects.get_custom_object_nodes(output)
        
        for stats in node_details['items']:
            cpu = round(int(stats['usage']['cpu'].strip('n')) / 1000000, 1)
            #memory = round(int(stats['usage']['memory'].strip('Ki')) / 1000000, 1)
            if 'Mi' in stats['usage']['memory']:
                memory = int(stats['usage']['memory'].strip('Mi'))
            else:
                memory = round(int(stats['usage']['memory'].strip('Ki')) / 1000000, 2)            
            total_cpu += cpu
            total_mem += memory
            data.append([stats['metadata']['name'], str(math.ceil(cpu)) + 'm', str(memory)])
        data.append(['\nTotal:', '\n' + str(math.ceil(total_cpu)) + 'm', '\n' + str(round(total_mem, 2)) + ' GB'])
        data = Output.bar(data, 'cpu', 'node')
        headers = ["NODE_NAME", "CPU_USED", "%AGE_CLUSTER_TOTAL_CPU", "MEM_USED(GB)", "%AGE_CLUSTER_TOTAL_MEM"]
        Output.print_table(data, headers, True)

    def get_pods(output):
        pod_details = K8sCustomObjects.get_custom_object_pods(output)
        return pod_details   

    def get_resource_usage_by_pod(output, sort):
        data, total_cpu, total_mem = [], 0, 0
        pod_details = K8sToppur.get_pods(output)
        for stats in pod_details['items']:
            cpu, mem = 0, 0
            
            for container in stats['containers']:
                if 'u' in container['usage']['cpu']:
                    cpu = cpu + int(container['usage']['cpu'].strip('u')) / 1000000000
                else:
                    cpu = cpu + int(container['usage']['cpu'].strip('n')) /  1000000
                if 'Mi' in container['usage']['memory']:
                    mem = mem + int(container['usage']['memory'].strip('Mi')) 
                else:
                    mem = mem + int(container['usage']['memory'].strip('Ki')) / 1000
                total_cpu += cpu
                total_mem += mem                      
            data.append([stats['metadata']['name'], math.ceil(cpu) , round(mem, 2), stats['metadata']['namespace']])
            
        headers = ["POD_NAME" , "CPU_USED", "MEMORY_USED(MB)", "NAMSPACE"]
        data = Output.sort_data(data, sort)
        data.append(['\nTotal:', '\n' + str(math.ceil(total_cpu)) + 'm', '\n' + str(round(total_mem / 1000 , 2)) + ' GB', ''])        
        Output.print_table(data, headers, True)
      
    def get_resource_usage_by_ns(output, sort):
        data, total_cpu, total_mem = [], 0, 0

        ns_details = K8sNameSpace.get_ns()
        pod_details = K8sToppur.get_pods(output)
        for item in ns_details.items:
            ns_cpu, ns_mem = 0, 0
            for stats in pod_details['items']:
                pod_ns = stats['metadata']['namespace']
                if item.metadata.name in pod_ns:
                    pod_mem, pod_cpu = 0, 0
                    for container in stats['containers']:
                        if 'u' in container['usage']['cpu']:
                        #print(container['usage']['cpu'], stats['metadata']['name'])
                            pod_cpu = int(container['usage']['cpu'].strip('u')) / 1000000000
                        else:
                            pod_cpu = int(container['usage']['cpu'].strip('n')) / 1000000
                        if 'Mi' in container['usage']['memory']:
                            pod_mem = int(container['usage']['memory'].strip('Mi'))
                        else:
                            pod_mem = round(int(container['usage']['memory'].strip('Ki')) / 1000, 2)
                        #print(stats['metadata']['name'], pod_mem, container['usage']['cpu'])
                        ns_mem += pod_mem
                        ns_cpu += pod_cpu
            total_cpu += ns_cpu
            total_mem += ns_mem  
            data.append([item.metadata.name, math.ceil(ns_cpu), round(ns_mem, 2)])
        
        if 'mem' in sort: data.sort(key=lambda x: x[2])
        if 'cpu' in sort: data.sort(key=lambda x: x[1])
        data = Output.sort_data(data, sort)
        data.append(['Total:', str(math.ceil(total_cpu)) + 'm', str(round(total_mem / 1000, 2)) + ' GB'])
        headers = ["NAMESPACE" , "CPU_USED", "MEMORY_USED(MB)"]
        Output.print_table(data, headers, True)

    def get_namespaced_resource_usage(output, ns, sort):
        data, total_cpu, total_mem = [], 0, 0
        pod_details = K8sCustomObjects.get_custom_object_namespaced_pods(output, ns)
        for stats in pod_details['items']:
            cpu, mem = 0, 0
            
            for container in stats['containers']:
                if 'u' in container['usage']['cpu']:
                    cpu = cpu + int(container['usage']['cpu'].strip('u')) / 1000000000
                else:
                    cpu = cpu + int(container['usage']['cpu'].strip('n')) / 1000000
                if 'Mi' in container['usage']['memory']:
                    mem = mem + int(container['usage']['memory'].strip('Mi')) 
                else:
                    mem = mem + int(container['usage']['memory'].strip('Ki')) / 1000
                total_cpu += cpu
                total_mem += mem                      
            data.append([stats['metadata']['name'], math.ceil(cpu), round(mem, 2), stats['metadata']['namespace']])
            
        headers = ["POD_NAME" , "CPU_USED", "MEMORY_USED(MB)", "NAMSPACE"]
        data = Output.sort_data(data, sort)
        data.append(['\nTotal:', '\n' + str(math.ceil(total_cpu)) + 'm', '\n' + str(round(total_mem / 1000, 2)) + ' GB', ''])        
        Output.print(data, headers, output)


def main():
    urllib3.disable_warnings()
    options = GetOpts.get_opts()
    if options[0]:
        usage()

    if 'namespace' in options[5] and not options[2]:
        K8sToppur.get_resource_usage_by_ns(options[3], options[4])
    elif 'pod' in options[5] and not options[2]:
        K8sToppur.get_resource_usage_by_pod(options[3], options[4])
    elif options[2]:
        K8sToppur.get_namespaced_resource_usage(options[3], options[2], options[4])
    else:  
        K8sToppur.get_nodes(options[3], options[4])
    Output.time_taken(start_time)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("[ERROR] Interrupted from keyboard!")
        try:
            sys.exit(0)
        except SystemExit:
            os._exit(0)