from columnar import columnar
from click import style
from packaging import version
import os, re, time, requests, json
from .logging import Logger

class Output:
    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    CYAN = '\033[36m'
    RESET = '\033[0m'
    BOLD = '\033[1;30m'
    # u'\u2717' means values is None or not defined
    # u'\u2714' means value is defined

    global patterns, _logger
    
    patterns = [(u'\u2714', lambda text: style(text, fg='green')), \
                ('True', lambda text: style(text, fg='green')), \
                ('False', lambda text: style(text, fg='yellow'))]

    def time_taken(start_time):
        print(Output.GREEN + "\nTotal time taken: " + Output.RESET + \
        "{}s".format(round((time.time() - start_time), 2)))

    # prints separator line between output
    def separator(color, char, l):
        if l: return
        columns, rows = os.get_terminal_size(0)
        for i in range(columns):
            print (color + char, end="" + Output.RESET)
        print ("\n")

    # sorts data by given field
    def sort_data(data, sort):
        if 'mem' in sort:
            data.sort(key=lambda x: x[2])
        elif 'cpu' in sort:
            data.sort(key=lambda x: x[1])
        else:
            data.sort(key=lambda x: x[0])
        return data


    # prints table from lists of lists: data
    def print_table(data, headers, verbose):
        if verbose and len(data) != 0:
            table = columnar(data, headers, no_borders=True, row_sep='-')
            print (table)
        else:
            return

    # prints analysis in bar format with %age, count and message
    def bar(data, resource, k8s_object):
        total_cpu = re.sub('[^0-9]','', data[-1][1])
        total_mem = re.sub('[^0-9]','', data[-1][2])
        i = 0
        for line in data:
            show_bar = []
            cpu_used = re.sub('[^0-9]','', line[1])
            mem_used = re.sub('[^0-9]','', line[2])
            cpu_percentage = round((100 * int(cpu_used) / int(total_cpu)), 2)
            mem_percentage = round((100 * int(mem_used) / int(total_mem)), 2)

            for i in range(15):
                if int(i) < cpu_percentage / 4:
                    show_bar.append(u'\u2588')
                else:
                    show_bar.append(u'\u2591')
            if 'Total:' not in line[0]:
                line.insert(2, "{} {}%".format("".join(show_bar), round(cpu_percentage, 1)))
                line.append("{} {}%".format("".join(show_bar), round(mem_percentage, 1)))
            else:
                line.insert(2, '')
                line.append('')
            
        return data
        
