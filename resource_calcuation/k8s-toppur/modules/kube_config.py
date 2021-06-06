from kubernetes import config, client

class KubeConfig:
    def load_kube_config(output, logger):
        try:
            #logger.info("Using kubeconfig from env.")
            config.load_kube_config()
            configuration = client.Configuration().get_default_copy()
            configuration.verify_ssl = False
        except:
            configuration = config.load_incluster_config()
        return configuration
