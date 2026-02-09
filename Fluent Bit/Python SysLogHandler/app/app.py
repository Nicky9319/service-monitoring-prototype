import logging
import logging.handlers
import socket
import json
import time

logger = logging.getLogger("python.host.app")
logger.setLevel(logging.INFO)

handler = logging.handlers.SysLogHandler(
    address=("127.0.0.1", 5140),
    socktype=socket.SOCK_DGRAM
)

class HostnameFilter(logging.Filter):
    hostname = socket.gethostname()
    def filter(self, record):
        record.hostname = self.hostname
        return True

formatter = logging.Formatter(
    "%(asctime)s %(hostname)s %(name)s[%(process)d]: %(levelname)s %(message)s",
    datefmt="%b %d %H:%M:%S"
)

handler.setFormatter(formatter)
handler.addFilter(HostnameFilter())
logger.addHandler(handler)

logger.info("host python syslog started")

i = 0
while True:
    logger.info(json.dumps({
        "service": "host-app",
        "env": "local",
        "iteration": i,
        "event": "heartbeat"
    }))
    time.sleep(2)
    i += 1
