import kubernetes.client
from kubernetes.client.rest import ApiException

class GetNodes:
    def get_nodes(logger, k8s_config):
        with kubernetes.client.ApiClient(k8s_config) as api_client:
            core = kubernetes.client.CoreV1Api(api_client)    
        logger.info ("Fetching nodes details\n")
        try:
            node_list = core.list_node(timeout_seconds=10)
            return node_list
        except ApiException as e:
            logger.info("Exception when calling CoreV1Api->list_node: %s\n" % e)