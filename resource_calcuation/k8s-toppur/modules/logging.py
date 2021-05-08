import logging

class Logger():
    def get_logger(class_name, format):
        logger = logging.getLogger(class_name)
        logger.setLevel(logging.INFO)

        if format == 'json':
            formatter = logging.Formatter('{"time": "%(asctime)s", "class": "%(name)s", "log_level": "%(levelname)s", "log": "%(message)s"}')
        else:
            formatter = logging.Formatter("[%(levelname)s] %(asctime)s  %(message)s")
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.DEBUG)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

        return logger