import argparse

class ArgParse:
    def arg_parse():
        p = argparse.ArgumentParser(description='k8s-manta-ray is a tool for k8s-day2-ops to work with pods.')
        p.add_argument('-a', '--action', help='mode of crud operations')
        p.add_argument('-b', '--body', nargs = 1, help="JSON file to be processed", type=argparse.FileType('r'))
        p.add_argument('-f', '--format', default='json', help='input format of patch body json|yaml.')
        p.add_argument('-k', '--kubeconfig', help='pass kubeconfig of the cluster. If not passed, picks KUBECONFIG from env')
        p.add_argument('-N', '--name', help='name of k8s object') 
        p.add_argument('-n', '--namespace', default='pods', help='k8s object type')   
        p.add_argument('-o', '--object', default='pods', help='k8s object type')  
        p.add_argument('-s', '--status', help='mode of crud operations')
        p.add_argument('-t', '--timer', default=30, help='set watch frequency for events. default is 30s')
        p.add_argument('--dryrun', default=False, action='store_true', help='sets dry-run mode. doesn not apply chnages.')
        p.add_argument('--loglevel', default='INFO', help='sets logging level info|debug|silent. default is INFO')
        p.add_argument('--output', help="pass json for logging in JSON output. default is text")
        args = p.parse_args()
        return args