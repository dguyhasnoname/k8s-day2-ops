from packaging import version
import os, re, time, json, csv, math
from tabulate import tabulate

class Output:
    RED = '\033[41m'
    ORANGE = '\033[91m'
    GREEN = '\033[32m'
    YELLOW = '\033[43m'
    LIGHTYELL = '\033[33m'
    RESET = '\033[0m'
    BOLD = '\033[1;30m'
    MARKER = u"\u2309\u169B\u22B8"
    FALSE = RED + 'False' + RESET
    TRUE = GREEN + 'True' + RESET

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
    def sort_data(data, headers, sort, logger):
        count, i = 0, 0
        if sort:
            for head in headers:
                head = head.lower()
                sort = sort.lower()
                if sort in head:
                    i = count
                count += 1
        try:
            data.sort(key=lambda x: x[i])
        except IndexError as e:
            logger.error("Issue in data: {}".format(e))
        return data

    # prints table from lists of lists: data
    def print_table(data, headers, logger):
        logger.info("Generating data in table format.")
        # temp_data = [x[:4] for x in data]
        print(tabulate(data, showindex=False, headers=headers, tablefmt='plain'))
 
    # prints data in tree format from lists data and headers
    def print_tree(data, headers, logger):
        logger.info("Generating data in tree format.")
        h = sorted(headers[1:], key=len)    # sorting to find longest element in headers for :
        for d in data:
            heading = headers[0] + ": "
            Output.separator(Output.YELLOW, '.' , '')
            print(Output.BOLD + heading + str(d[0]) + Output.RESET)

            # printing the tree
            for i in range(len(headers)):
                
                try:
                    if not '\n' in str(d[i+1]):                        
                        print("".ljust(len(heading)) + Output.MARKER + headers[i+1].ljust(len(h[-1])) + ": " + str(d[i+1]))
                    else:
                        i_padding = "".ljust(len(heading)) + Output.MARKER + headers[i+1] + ": "
                        print(i_padding)

                        for x in d[i+1].split("\n"):
                            if '[' in x:
                                x = ast.literal_eval(x)
                        
                                for j in x:
                                    y_padding = len(i_padding + Output.MARKER + previous)
                                    if y_padding > 50: y_padding = 50
                                    print("".ljust(y_padding) + Output.MARKER + str(j))
                            else:
                                if x:
                                    print("".ljust(len(i_padding)) + Output.MARKER + str(x))
                                previous = str(x)
                except:
                    pass

    # prints data in json format from lists data and headers
    def print_json(data, headers, logger):
        json_data = []
        headers = [x.lower() for x in headers]
        logger.info("Generating data in json format.")
        for item in data:
            temp_dic = {}
            # storing json data in dict for each list in data
            for i in range(len(headers)):
                for j in range(len(item)):
                    if not '\n' in str(item[i]):
                        temp_dic.update({headers[i]: item[i]})
                    else:
                        item[i].split("\n")
                        temp_dic.update({headers[i]: item[i].split("\n")})

            # appending all json dicts to form a list
            json_data.append(temp_dic)
     
        print(json.dumps(json_data))

        directory = './reports/json/'
        if not os.path.exists(directory):
            os.makedirs(directory)
        # writing out json data in file based on object type and config being checked
        filename = directory + headers[0] + str(time.time()) + '_report.json'
        f = open(filename, 'w')
        f.write(json.dumps(json_data))
        f.close()
        logger.info("File generated: {}".format(filename))       
        return json.dumps(json_data)

    def csv_out(data, headers, logger):
        logger.info("Generating data in csv format.")
        directory = './reports/csv/'
        if not os.path.exists(directory):
            os.makedirs(directory)
        filename = directory + headers[0] + str(time.time()) + '_report.csv'
        with open(filename, "w", newline="") as file:
            writer = csv.writer(file, delimiter=',')
            writer.writerow(i for i in headers)
            for j in data:
                writer.writerow(j)
        logger.info("File generated: {}".format(filename))

    def bar(data, headers):
        i = 0
        for line in data:
            show_bar_1, show_bar_2 = [], []
            running_pods = line[1]
            faulty_pods = line[2]
            total_pods = line[3]
            try:
                running_percentage = float(100 * int(running_pods) / int(total_pods))
            except ZeroDivisionError:
                running_percentage = 0
            try:
                faulty_percentage = float(100 * int(faulty_pods) / int(total_pods))
            except ZeroDivisionError:
                faulty_percentage = 0
            
            for i in range(20):
                if int(i) < int(running_percentage) / 5:
                    show_bar_1.append(Output.GREEN + u'\u2588' + Output.RESET)
                else:
                    show_bar_1.append(u'\u2591')
                if int(i) < int(faulty_percentage) / 5:
                    show_bar_2.append(Output.ORANGE + u'\u2588' + Output.RESET)
                else:
                    show_bar_2.append(u'\u2591')
            
            line[1] = "{} {} {}%".format(str(running_pods).ljust(3, ' '), "".join(show_bar_1), round(running_percentage, 1))
            line[2] = "{} {} {}%".format(str(faulty_pods).ljust(3, ' '), "".join(show_bar_2), round(faulty_percentage, 1) )

        return data  

    def print(data, headers, format, logger, bar):
        headers = [x.upper() for x in headers]
        if 'json' in format:
            Output.print_json(data, headers, logger)
        elif 'tree' in format:
            Output.print_tree(data, headers, logger)
        elif 'csv' in format:
            Output.csv_out(data, headers, logger)
        else:
            if bar:
                data = Output.bar(data, headers)
            Output.print_table(data, headers, logger)      
        
    def summary(data, row_to_check, row_value):
        check = '--'
        for x in data:
            check = ''
            if type(row_value) == list:
                if any(i in str(x[row_to_check]) for i in row_value):
                    check = Output.TRUE
                else:
                    check = Output.FALSE
                    break                    
            else:
                if row_value == str(x[row_to_check]):
                    check = Output.TRUE
                else:
                    check = Output.FALSE
                    break
        return check