from kubernetes import client
from kubernetes.client.rest import ApiException
from .kube_config import kubeConfig



class K8sNameSpace:
    kubeConfig.load_kube_config(format)
    core = client.CoreV1Api()

    def get_ns():
        print ("\n[INFO] Fetching namespaces data...")
        try:
            ns_list = K8sNameSpace.core.list_namespace(timeout_seconds=10)
            return ns_list
        except ApiException as e:
            print("Exception when calling CoreV1Api->list_namespace: %s\n" % e)