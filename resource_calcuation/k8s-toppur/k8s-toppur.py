
import os, getopt, argparse, sys, time, math, urllib3
start_time = time.time()
from datetime import datetime, timezone
from modules.logging import Logger
from modules.getopts import GetOpts
from modules.kube_config import KubeConfig
from modules.get_custom_object import K8sCustomObjects
from modules.get_nodes import GetNodes
from modules.output import Output
from modules.get_ns import K8sNameSpace

def usage():
    parser=argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""This script can be used to see resource usage in kubernetes cluster.

Before running script export KUBECONFIG file as env:
    export KUBECONFIG=<kubeconfig file location>
    
    e.g. export KUBECONFIG=/Users/dguyhasnoname/kubeconfig\n""",
        epilog="""All's well that ends well.""")
    
    parser.add_argument('-s', '--sort', action="store_true", \
        help="sort by cpu/memory. Default sorting is by name.")
    parser.add_argument('-n', '--namespace', action="store_true", \
        help="check resources in specific namespace. Comma separated multiple namespace supported")
    parser.add_argument('-f', '--filter', action="store_true", \
        help="filter resource usage by pods/pod_string in overall cluster." \
            "Comma separated multiple pods supported")
    parser.add_argument('-o', '--output', action="store_true", \
        help="output formats csv|json|tree. Default is text on stdout.")
    parser.add_argument('-p', '--pods', action="store_true", \
        help="filter resource usage by pod name in overall cluster."\
            "Comma separated multiple pods supported")        
    parser.parse_args()

class K8sToppur():
    def __init__(self, k8s_config, logger, output):
        self.logger = logger  
        self.k8s_config = k8s_config
        self.output = output
        self.call = K8sCustomObjects(self.output, self.k8s_config, self.logger)

    def get_nodes(self, sort):
        """
        collects resource usage by node. Verfied o/p from 
        kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes \
            | jq -r '.items[].usage.memory' | sed 's/[^0-9]*//g'  \
            |  awk '{ sum += $1 } END { print sum }' 
        """
        data = [] 
        total_cpu_used, total_mem_used, total_cpu_capacity, \
            total_mem_capacity, node_count = [0] * 5
        self.logger.info("Getting node details.")
        node_metric_details = self.call.get_custom_object_nodes()
        node_object = GetNodes.get_nodes(self.logger, self.k8s_config)
        
        for stats in node_metric_details['items']:
            node_cpu, node_mem = [''] * 2
            for node in node_object.items:
                if node.metadata.name in stats['metadata']['name']:
                    node_cpu = int(node.status.capacity['cpu'])
                    node_mem = math.ceil(int(node.status.capacity['memory'].strip('Ki'))/1000000)
                    node_role = node.metadata.labels['node.kubernetes.io/role']
            used_cpu = math.ceil(int(stats['usage']['cpu'].strip('n')) / 1000000)
            if 'Mi' in stats['usage']['memory']:
                used_memory = round(int(stats['usage']['memory'].strip('Mi')) / 1000 , 1)
            else:
                used_memory = round(int(stats['usage']['memory'].strip('Ki')) / 1000000, 1)            
            total_cpu_used += used_cpu
            total_mem_used += used_memory
            total_cpu_capacity += node_cpu
            total_mem_capacity += node_mem
            node_count += 1
            data.append([stats['metadata']['name']+ ' [' + node_role + ']', \
                        str(used_cpu) + 'm', str(node_cpu), \
                        str(used_memory), str(node_mem)])
        data = Output.bar(data)
        for x in data:
            x[1] = x[1] + Output.GREEN + '/' + x[2] + Output.RESET 
            x[4] = x[4] + Output.CYAN + '/' + x[5] + Output.RESET 
            x.pop(2)
            x.pop(4)
        data.append([])
        data.append([Output.TOTAL + str(node_count), \
                    str(math.ceil(total_cpu_used)) + 'm/' + \
                    str(math.ceil(total_cpu_capacity)), '', \
                    str(round(total_mem_used, 2)) + '/' + \
                    str(math.ceil(total_mem_capacity)) + ' GB', ''])
        headers = ["NODE_NAME", "CPU_USED/TOTAL", \
                   "%AGE_CPU_USAGE", "MEM_USED/TOTAL(GB)", \
                   "%AGE_MEM_USAGE"]
        Output.print(data, headers, self.output)

    def get_pods(self):
        pod_details = self.call.get_custom_object_pods()
        return pod_details   

    def get_resource_usage_by_pod(self, sort, filter):
        data, total_cpu, total_mem = [], 0, 0
        pod_details = K8sToppur.get_pods(self)
        if ',' in filter:
            filter = filter.split(',')
        else:
            filter = [filter]
        for stats in pod_details['items']:
            cpu, mem = 0, 0
            if any(x in stats['metadata']['name'] for x in filter):
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
                data.append([stats['metadata']['name'], str(math.ceil(cpu)) +'m  ' , \
                            str(round(mem, 2)) + "Mi", stats['metadata']['namespace']])

        data = Output.sort_data(data, sort)
        #data.append(['\nTotal:', '\n' + str(math.ceil(total_cpu)) + 'm', '\n' + str(round(total_mem / 1000 , 2)) + ' GB', ''])
        headers = ["POD_NAME" , "CPU_USED", "MEMORY_USED(MB)", "NAMSPACE"]         
        Output.print(data, headers, self.output)
      
    def get_resource_usage_by_ns(self, sort):
        data = []
        total_cpu, total_mem , ns_count = [0] * 3

        ns_details = K8sNameSpace.get_ns(self.logger, self.k8s_config)
        pod_details = K8sToppur.get_pods(self)
        for item in ns_details.items:
            ns_cpu, ns_mem = 0, 0
            for stats in pod_details['items']:
                pod_ns = stats['metadata']['namespace']
                if item.metadata.name in pod_ns:
                    pod_mem, pod_cpu = 0, 0
                    for container in stats['containers']:
                        if 'u' in container['usage']['cpu']:
                            pod_cpu = math.ceil(int(container['usage']['cpu'].strip('u')) / 1000000000)
                        else:
                            pod_cpu = math.ceil(int(container['usage']['cpu'].strip('n')) / 1000000)
                        if 'Mi' in container['usage']['memory']:
                            pod_mem = int(container['usage']['memory'].strip('Mi'))
                        else:
                            pod_mem = round(int(container['usage']['memory'].strip('Ki')) / 1000, 2)
                        ns_mem += pod_mem
                        ns_cpu += pod_cpu
            total_cpu += ns_cpu
            total_mem += ns_mem
            ns_count += 1  
            data.append([item.metadata.name, str(ns_cpu) + 'm',  str(round(ns_mem / 1000, 2))])
        
        if 'mem' in sort: data.sort(key=lambda x: x[2])
        if 'cpu' in sort: data.sort(key=lambda x: x[1])
        data = Output.sort_data(data, sort)
        for line in data:
            line.insert(2, str(total_cpu) + 'm')
            line.append(str(round(total_mem / 1000, 2)))
    
        data = Output.bar(data)
        for line in data:
            line.pop(2)
            line.pop(4)    
        data.append([])        
        data.append([Output.TOTAL + str(ns_count), \
                    str(math.ceil(total_cpu)) + 'm', '', \
                    str(round(total_mem / 1000, 2)) + ' GB'])
        headers = ["NAMESPACE" , "CPU_USED", "%AGE_NS_TOTAL_CPU", \
                    "MEMORY_USED(GB)", "%AGE_NS_TOTAL_MEM"]
        Output.print(data, headers, self.output)

    def get_namespaced_resource_usage(self, ns, sort):
        if ',' in ns:
            ns_list = ns.split(',')
        else:
            ns_list = [ns]
        for item in ns_list:
            data, total_cpu, total_mem, total_pods = [], 0, 0, 0
            pod_details = self.call.get_custom_object_namespaced_pods(self.output, item)
            for stats in pod_details['items']:
                cpu, mem = 0, 0
                if stats['metadata']['namespace'] in item:
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
                        total_pods += 1                 
                        data.append([stats['metadata']['name'], str(math.ceil(cpu)) + 'm', \
                                    round(mem, 2), stats['metadata']['namespace']])
                
            headers = ["POD_NAME" , "CPU_USED", "MEMORY_USED(MB)", "NAMSPACE"]
            data = Output.sort_data(data, sort)
            data.append([])
            data.append([Output.TOTAL + str(total_pods), str(math.ceil(total_cpu)) + 'm', \
                        str(round(total_mem / 1000, 2)) + ' GB', ''])
                 
            Output.print(data, headers, self.output)


def main():
    urllib3.disable_warnings()
    options = GetOpts.get_opts()
    logger = Logger.get_logger(options[3])
    k8s_config = KubeConfig.load_kube_config(options[3], logger)
    call = K8sToppur(k8s_config, logger, options[3])
    if options[0]:
        usage()
    # options = [help, pods, ns, output, sort, filter]
    
    if 'namespace' in options[5] and not options[2]:
        call.get_resource_usage_by_ns(options[4])
    elif options[5] or options[1]:
        pods = options[5] or options[1]
        call.get_resource_usage_by_pod(options[4], pods)
    elif options[2]:
        call.get_namespaced_resource_usage(options[2], options[4])
    else:  
        call.get_nodes(options[4])
        call.get_resource_usage_by_ns(options[4])
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