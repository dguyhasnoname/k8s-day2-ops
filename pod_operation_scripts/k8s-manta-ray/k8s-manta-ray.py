import os, argparse, sys, time, urllib3, json, yaml
start_time = time.time()
from modules.logging import Logger
from modules.argparse import ArgParse
from modules.kube_config import KubeConfig
from modules.output import Output
from modules.pod_crud import PodCrud

class MantaRay():
    def __init__(self, logger, k8s_config, output):
        self.logger = logger  
        self.k8s_config = k8s_config
        self.output = output

    def pod_crud_operations(self, args):
        x = PodCrud(self.logger, self.k8s_config, self.output)
        pod_data = x.get_pods(args.namespace)
        if args.action in ['delete', 'del']:
            x.delete_pods(args.namespace, args.name, args.status, args.dryrun, pod_data)

def main():
    urllib3.disable_warnings()
    args = ArgParse.arg_parse()
    # [help, action, body, format, kubeconfig, object_name, \
    # namespace, object, status, dryrun, loglevel, log_output_format]
    logger = Logger.get_logger(args.output, args.loglevel)
    k8s_config = KubeConfig.load_kube_config(args.output, \
                                logger, args.kubeconfig)
    if args.body:
        if 'json' in args.input:
            body = json.load(args.body[0])
        elif 'yaml' in args.input:
            body = yaml.load(args.body[0], yaml.Loader)
        else:
            logger.warning("Invalid format of patch body passed")
    else:
        body = ''
    call = MantaRay(logger, k8s_config, args.output)
    call.pod_crud_operations(args)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("[ERROR] Interrupted from keyboard!")
        try:
            sys.exit(0)
        except SystemExit:
            os._exit(0)