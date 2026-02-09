#!/usr/bin/env bash

set -e

PROJECT_ROOT=$(pwd)

echo "🚀 Initializing Python → Syslog → Fluent Bit prototype..."

# ----------------------------
# Create directories
# ----------------------------
mkdir -p app fluent-bit

# ----------------------------
# Python app
# ----------------------------
cat << 'EOF' > app/app.py
import logging
import logging.handlers
import socket
import json
import time

logger = logging.getLogger("python.syslog.demo")
logger.setLevel(logging.INFO)

handler = logging.handlers.SysLogHandler(
    address=("fluent-bit", 5140),
    socktype=socket.SOCK_DGRAM
)

class HostnameFilter(logging.Filter):
    hostname = socket.gethostname()

    def filter(self, record):
        record.hostname = self.hostname
        return True

formatter = logging.Formatter(
    "%(asctime)s %(hostname)s %(name)s[%(process)d]: %(levelname)s %(message)s"
)

handler.setFormatter(formatter)
handler.addFilter(HostnameFilter())
logger.addHandler(handler)

logger.info("python syslog demo started")

i = 0
while True:
    payload = {
        "service": "demo-service",
        "env": "local",
        "iteration": i,
        "event": "heartbeat"
    }
    logger.info(json.dumps(payload))
    time.sleep(2)
    i += 1
EOF

# ----------------------------
# Fluent Bit config
# ----------------------------
cat << 'EOF' > fluent-bit/fluent-bit.conf
[SERVICE]
    Flush        1
    Log_Level    info

[INPUT]
    Name        syslog
    Mode        udp
    Listen      0.0.0.0
    Port        5140
    Parser      syslog-rfc5424
    Tag         python.syslog

[FILTER]
    Name        parser
    Match       python.syslog
    Key_Name    message
    Parser      json
    Reserve_Data true

[OUTPUT]
    Name   stdout
    Match  *
EOF

# ----------------------------
# Fluent Bit Dockerfile
# ----------------------------
cat << 'EOF' > fluent-bit/Dockerfile
FROM fluent/fluent-bit:2.2

COPY fluent-bit.conf /fluent-bit/etc/fluent-bit.conf

CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf"]
EOF

# ----------------------------
# Docker Compose
# ----------------------------
cat << 'EOF' > docker-compose.yml
version: "3.8"

services:
  fluent-bit:
    build: ./fluent-bit
    container_name: fluent-bit
    ports:
      - "5140:5140/udp"

  python-app:
    image: python:3.11-slim
    container_name: python-syslog-app
    depends_on:
      - fluent-bit
    volumes:
      - ./app:/app
    working_dir: /app
    command: ["python", "app.py"]
EOF

# ----------------------------
# Final output
# ----------------------------
echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1️⃣  docker compose up --build"
echo "2️⃣  Watch logs flowing via syslog → Fluent Bit"
echo ""
echo "To stop:"
echo "🛑 docker compose down"
