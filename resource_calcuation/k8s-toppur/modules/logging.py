import logging

class Logger():
    def get_logger(format):
        logger = logging.getLogger()
        logger.setLevel(logging.INFO)
        if format == 'json':
            formatter = logging.Formatter('{"time": "%(asctime)s", "origin": "p%(process)s %(filename)s:%(name)s:%(lineno)d", "log_level": "%(levelname)s", "log": "%(message)s"}')
        else:
            formatter = logging.Formatter("[%(levelname)s] %(asctime)s p%(process)s %(filename)s:%(name)s:%(lineno)d %(message)s")
        console_handler = logging.StreamHandler()

        # if silent:
        #     console_handler.setLevel(logging.WARNING)
        #     console_handler.setFormatter(formatter)
        #     logger.addHandler(console_handler) 
        # else:
        console_handler.setLevel(logging.DEBUG)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

        return logger