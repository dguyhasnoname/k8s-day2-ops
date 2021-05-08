import kubernetes.client
from kubernetes.client.rest import ApiException
from .kube_config import kubeConfig
from .logging import Logger


class K8sCustomObjects():
    def __init__(self, output):
        global format
        self.output = output
        format = output
        
    configuration = kubeConfig.load_kube_config(format)
    with kubernetes.client.ApiClient(configuration) as api_client:
        api = kubernetes.client.CustomObjectsApi(api_client)        

    def get_custom_object_nodes(output):
        _logger = Logger.get_logger('K8sCustomObjects', output)
        
        try:
            _logger.info("Fetching nodes data...\n") 
            nodes = K8sCustomObjects.api.list_cluster_custom_object("metrics.k8s.io", "v1beta1", "nodes")
            return nodes
        except ApiException as e:
            _logger.info("Exception when calling CustomObjectsApi->list_cluster_custom_object: %s\n" % e)

    def get_custom_object_pods(output):
        _logger = Logger.get_logger('K8sCustomObjects', output)
        
        try:
            _logger.info("Fetching pods data...\n") 
            pods = K8sCustomObjects.api.list_cluster_custom_object("metrics.k8s.io", "v1beta1", "pods")
            return pods
        except ApiException as e:
            _logger.info("Exception when calling CustomObjectsApi->list_cluster_custom_object: %s\n" % e)

    def get_custom_object_namespaced_pods(output, ns):
        _logger = Logger.get_logger('K8sCustomObjects', output)
        
        try:
            _logger.info("Fetching pods data in namespace {}s...\n".format(ns)) 
            namespace = ns
            ns_pods = K8sCustomObjects.api.list_namespaced_custom_object("metrics.k8s.io", "v1beta1", ns, 'pods')
            return ns_pods
        except ApiException as e:
            _logger.info("Exception when calling CustomObjectsApi->list_cluster_custom_object: %s\n" % e) 