import kubernetes.client
from kubernetes.client.rest import ApiException

class K8sCustomObjects():
    def __init__(self, output, k8s_config, logger):
        self.output = output
        self.logger = logger
        self.k8s_config = k8s_config
        with kubernetes.client.ApiClient(self.k8s_config) as api_client:
            self.api = kubernetes.client.CustomObjectsApi(api_client)        

    def get_custom_object_nodes(self):
        try:
            self.logger.info("Fetching node metrics data...") 
            nodes = self.api.list_cluster_custom_object("metrics.k8s.io", "v1beta1", "nodes")
            return nodes
        except ApiException as e:
            self.logger.info("Exception when calling CustomObjectsApi->list_cluster_custom_object: %s\n" % e)

    def get_custom_object_pods(self):
        try:
            self.logger.info("Fetching pod metrics data...") 
            pods = self.api.list_cluster_custom_object("metrics.k8s.io", "v1beta1", "pods")
            return pods
        except ApiException as e:
            self.logger.info("Exception when calling CustomObjectsApi->list_cluster_custom_object: %s\n" % e)

    def get_custom_object_namespaced_pods(self, output, ns):
        try:
            self.logger.info("Fetching pods data in namespace {}...\n".format(ns)) 
            ns_pods = self.api.list_namespaced_custom_object("metrics.k8s.io", "v1beta1", ns, 'pods')
            return ns_pods
        except ApiException as e:
            self.logger.info("Exception when calling CustomObjectsApi->list_cluster_custom_object: %s\n" % e) 