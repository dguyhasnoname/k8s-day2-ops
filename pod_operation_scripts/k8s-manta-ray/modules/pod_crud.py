import kubernetes.client
from kubernetes.client.rest import ApiException

class PodCrud:
    def __init__(self, logger, k8s_config, output):
        with kubernetes.client.ApiClient(k8s_config) as api_client:
            core = kubernetes.client.CoreV1Api(api_client)
        self.core = core
        self.logger = logger
        self.output = output          

    def get_pods(self, namespace):
        try:
            if namespace == 'all':
                self.logger.info ("Fetching all namespace pods data.")         
                pods = self.core.list_pod_for_all_namespaces(timeout_seconds=10)
                self.logger.info ("Fetched pod data for all pods")
            else:
                self.logger.info ("Fetching {} namespace pods data.".format(namespace))
                pods = self.core.list_namespaced_pod(namespace, timeout_seconds=10)
                self.logger.info ("Fetched pod data for ns")
            return pods
        except ApiException as e:
            self.logger.warning("Exception when calling CoreV1Api->list_pod_for_all_namespaces: %s\n" % e)


    def delete_pods(self, ns, pod_name, status, dryrun, pod_data):

        def delete_namespaced_pod(name, namespace, dry_run=dryrun):
            if dryrun:
                self.logger.info ("Dryrun enabled. Changes won't be applied")
                try:
                    self.core.delete_namespaced_pod(name, namespace, dry_run='All')
                except ApiException as e:
                    print("Exception when calling CoreV1Api->delete_namespaced_pod: %s\n" % e)                     
            else:
                try:
                    self.core.delete_namespaced_pod(name, namespace, grace_period_seconds=0)
                except ApiException as e:
                    print("Exception when calling CoreV1Api->delete_namespaced_pod: %s\n" % e)                    
        
        if status and not pod_name:
            for pod in pod_data.items:
                name = pod.metadata.name
                namespace = pod.metadata.namespace
                if pod.status.phase in ['Pending', 'Failed', 'Unknown']:
                    self.logger.warning("Pod {} found in {} phase in namespace {}. Removing the pod.".format(name, pod.status.phase, namespace))
                    delete_namespaced_pod(name, namespace, dry_run=dryrun)
                elif pod.status.phase in 'Running':
                    for container in pod.status.container_statuses:
                        if 'False' in str(container.ready):
                            self.logger.warning("Container {} of pod {} with Running phase in namespace {} found in NotReady state. Checking the reason".format(container.name, name, namespace))
                            try:
                                if container.state.waiting is not None:
                                    self.logger.warning("Container {} of pod {} in namespace {} is waiting for {}".format(container.name, name, namespace, container.state.waiting.reason))
                                    if status in container.state.waiting.reason:
                                        self.logger.info("Removing pod {} in namespace {}".format(name, namespace))
                                        delete_namespaced_pod(name, namespace, dry_run=dryrun)
                            except:
                                pass
                elif pod.status.phase in 'Succeeded':
                    self.logger.debug("Pod {} found in {} phase in namespace {}.".format(name, pod.status.phase, namespace))
                else:
                    self.logger.debug("Pod {} found in {} phase in namespace {}. Unknown state.".format(name, pod.status.phase, namespace))
        
        if pod_name:
            for pod in pod_data.items:
                name = pod.metadata.name
                namespace = pod.metadata.namespace
                if pod_name in name:
                    if not status:
                        self.logger.info("Pod {} found in namespace {}. Removing the pod.".format(name, namespace))
                        delete_namespaced_pod(name, namespace, dry_run=dryrun)
                    else:
                        for container in pod.status.container_statuses:
                            try:
                                if container.state.terminated.reason is not None and status in container.state.terminated.reason:
                                        self.logger.info("Pod {} with container state {} found in namespace {}. Removing the pod".format(name, container.state.terminated.reason, namespace))
                                        delete_namespaced_pod(name, namespace, dry_run=dryrun)   
                                elif container.state.waiting.reason is not None and status in container.state.waiting.reason:
                                        self.logger.info("Pod {} with container state {} found in namespace {}. Removing the pod".format(name, container.state.waiting.reason, namespace))
                                        delete_namespaced_pod(name, namespace, dry_run=dryrun)
                                else:                               
                                    self.logger.warning("Pod's with name having string \'{}\' in namespace {} with status {} not found. Skipping the check".format(pod_name, status, namespace))
                            except:
                                pass