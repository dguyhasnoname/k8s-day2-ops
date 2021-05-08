import getopt, sys

class GetOpts:
    def get_opts():
        help, pods, ns, output, sort, filter ='', '', '', '', '', ''
        try:
            opts, args = getopt.getopt(sys.argv[1:], "hp:n:o:s:f:", ["help", "pods=", "namespace=", "output=", "sort=", "filter="])
        except getopt.GetoptError as err:
            print("[ERROR] {}. ".format(err) + \
            "Please run script with -h flag to see valid options.")
            sys.exit(0)

        for o, a in opts:
            if o in ("-h", "--help"):
                help = True
            elif o in ("-p", "--pods"):
                pods = a
            elif o in ("-n", "--namespace"):
                ns = a             
            elif o in ("-o", "--output"):
                output = a 
            elif o in ("-s", "--sort"):
                sort = a
            elif o in ("-f", "--filter"):
                filter = a                                                                        
 

        options = [help, pods, ns, output, sort, filter]
        return options 