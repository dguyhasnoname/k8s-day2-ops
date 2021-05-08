from kubernetes import config, client
from .logging import Logger

class kubeConfig:
    def load_kube_config(output):
        #_logger = Logger.get_logger('kubeConfig', output)
        try:
            #_logger.info("Using kubeconfig from env.")
            config.load_kube_config()
            configuration = client.Configuration().get_default_copy()
            configuration.verify_ssl = False
            return configuration
        except:
            pass
            #config.load_incluster_config()