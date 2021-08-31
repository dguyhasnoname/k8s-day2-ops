from kubernetes import config, client
from kubernetes.client.rest import ApiException
import os

class KubeConfig:
    def load_kube_config(output, logger, kubeconfig):
        try:
            configuration = config.load_incluster_config()
            logger.info("Using in-cluster kubeconfig for cluster")      
        except:
            try:
                if kubeconfig:
                    config.load_kube_config(config_file=kubeconfig)
                    logger.info("Using kubeconfig from passed argument {}".format(kubeconfig))
                else:
                    config.load_kube_config()
                    logger.info("Using kubeconfig from env KUBECONFIG {} for cluster".format(os.getenv('KUBECONFIG')))
            except ApiException as e:
                logger.warning("exception occured while loading kubeconfig: {}".format(e))
            configuration = client.Configuration().get_default_copy()
            configuration.verify_ssl = False
        return configuration