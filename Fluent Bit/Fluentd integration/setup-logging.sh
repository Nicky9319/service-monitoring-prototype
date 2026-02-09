#!/usr/bin/env bash
# setup-logging.sh
# Usage: ./setup-logging.sh [target-directory]
# If no directory provided, uses current directory.

set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
echo "Setting up logging project in: $TARGET_DIR"

# Ensure target dir exists
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# Prevent accidental overwrite
if [ -f "$TARGET_DIR/docker-compose.yml" ] || [ -d "$TARGET_DIR/fluent-bit" ] || [ -d "$TARGET_DIR/fluentd" ]; then
  echo "Warning: It looks like this directory already contains a logging project (docker-compose.yml or fluent-bit/fluentd)."
  read -p "Proceed and overwrite existing files? (y/N) " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborting."
    exit 1
  fi
fi

echo "Creating directory layout..."
rm -rf fluent-bit fluentd logs
mkdir -p fluent-bit
mkdir -p fluentd
mkdir -p fluentd/buffer
mkdir -p logs

echo "Writing docker-compose.yml..."
cat > docker-compose.yml <<'YAML'
version: "3.8"
services:
  fluent-bit:
    image: fluent/fluent-bit:latest
    container_name: fluent-bit
    volumes:
      - ./logs:/var/log/myapp:ro
      - ./fluent-bit/fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf:ro
      - ./fluent-bit/parsers.conf:/fluent-bit/etc/parsers.conf:ro
      - ./fluent-bit/state:/var/log/fluent-bit
    networks:
      - logging-net
    restart: unless-stopped

  fluentd:
    build:
      context: ./fluentd
    container_name: fluentd
    ports:
      - "24224:24224"
      - "24224:24224/udp"
    environment:
      AZURE_STORAGE_ACCOUNT: "${AZURE_STORAGE_ACCOUNT:-}"
      AZURE_STORAGE_ACCESS_KEY: "${AZURE_STORAGE_ACCESS_KEY:-}"
      AZURE_STORAGE_CONNECTION_STRING: "${AZURE_STORAGE_CONNECTION_STRING:-}"
      AZURE_CONTAINER: "${AZURE_CONTAINER:-logs}"
    volumes:
      - ./fluentd/fluent.conf:/fluentd/etc/fluent.conf:ro
      - ./fluentd/buffer:/var/log/fluent/buffer
    networks:
      - logging-net
    restart: unless-stopped

networks:
  logging-net:
    driver: bridge
YAML

echo "Writing fluent-bit/fluent-bit.conf..."
cat > fluent-bit/fluent-bit.conf <<'FB'
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info
    Parsers_File parsers.conf

[INPUT]
    Name        tail
    Path        /var/log/myapp/*.log
    Refresh_Interval 5
    Skip_Long_Lines On
    Tag         host.app
    DB          /var/log/fluent-bit/tail_db.sqlite

[OUTPUT]
    Name        forward
    Match       *
    Host        fluentd
    Port        24224
FB

echo "Writing fluent-bit/parsers.conf (basic placeholder)..."
cat > fluent-bit/parsers.conf <<'PC'
# Basic parsers file. Add JSON or regex parsers if needed.
[PARSER]
    Name        json
    Format      json
PC

echo "Writing fluentd/Dockerfile (installs azure plugin)..."
cat > fluentd/Dockerfile <<'DF'
FROM fluent/fluentd:latest

USER root

# Install the Azure append-blob plugin (LTS fork recommended)
# You may pin to specific versions if desired.
RUN fluent-gem install fluent-plugin-azure-storage-append-blob-lts --no-document

# Create buffer dir and set ownership
RUN mkdir -p /var/log/fluent/buffer && chown -R fluent:fluent /var/log/fluent

USER fluent

COPY fluent.conf /fluentd/etc/fluent.conf
DF

echo "Writing fluentd/fluent.conf..."
cat > fluentd/fluent.conf <<'FD'
<system>
  log_level info
</system>

<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>

<match **>
  @type copy

  <store>
    @type stdout
  </store>

  <store>
    @type azure-storage-append-blob
    azure_storage_account "#{ENV['AZURE_STORAGE_ACCOUNT']}"
    azure_storage_access_key "#{ENV['AZURE_STORAGE_ACCESS_KEY']}"
    azure_storage_connection_string "#{ENV['AZURE_STORAGE_CONNECTION_STRING']}"
    azure_container "#{ENV['AZURE_CONTAINER'] || 'logs'}"
    auto_create_container true
    path logs/
    azure_object_key_format %{path}%{time_slice}_%{index}.log
    time_slice_format %Y%m%d-%H
    <buffer tag,time>
      @type file
      path /var/log/fluent/buffer
      timekey 120
      timekey_wait 30
      timekey_use_utc true
    </buffer>
  </store>
</match>
FD

echo "Creating sample .env (with placeholder values) — edit this with your real Azure credentials!"
cat > .env <<'ENV'
# Replace these with your values or export them into your shell
AZURE_STORAGE_ACCOUNT=
AZURE_STORAGE_ACCESS_KEY=
# Or use AZURE_STORAGE_CONNECTION_STRING instead of account/key
AZURE_STORAGE_CONNECTION_STRING=
AZURE_CONTAINER=logs
ENV

echo "Creating sample log file: logs/app.log"
echo "sample log line $(date -u) - initial" > logs/app.log
chmod 644 logs/app.log

# Ensure fluent-bit state and buffer dirs exist
mkdir -p fluent-bit/state
mkdir -p fluent-bit/state
chmod -R 755 fluent-bit
chmod -R 755 fluentd
chmod -R 755 fluentd/buffer

echo
echo "Project files created in: $TARGET_DIR"
echo
echo "Next steps (1-2 minutes):"
echo "  1) Edit the .env file and add your Azure credentials (or export AZURE_STORAGE_* vars)."
echo "     - For local testing you can leave them blank and Fluentd will fail the Azure upload but stdout will still show logs."
echo "  2) Run: docker-compose up --build -d"
echo
echo "This script can optionally run docker-compose for you now. Do you want me to run 'docker-compose up --build -d' here? (y/N)"
read -r do_compose
if [[ "${do_compose,,}" == "y" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found in PATH. Install Docker first."
    exit 1
  fi
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "ERROR: docker-compose not found in PATH. Install docker-compose (or use 'docker compose' with Docker v2)."
    exit 1
  fi
  echo "Bringing up stack (this will build the Fluentd image)..."
  docker-compose up --build -d
  echo "Stack started. To follow Fluentd stdout logs run:"
  echo "  docker-compose logs -f fluentd"
  echo "To test the pipeline append a line into logs/app.log from the host:"
  echo "  echo \"test log $(date -u)\" >> logs/app.log"
else
  echo "OK — not starting Docker. Run the following when you're ready:"
  echo "  cd \"$TARGET_DIR\""
  echo "  docker-compose up --build -d"
  echo
  echo "Then to test:"
  echo "  echo \"hello $(date -u) test\" >> logs/app.log"
  echo "  docker-compose logs -f fluentd"
fi

echo
echo "Security note: do NOT commit .env or files containing your Azure keys into source control."
echo "If you prefer using a connection string or managed identity (on Azure VM/AKS), set AZURE_STORAGE_CONNECTION_STRING or use MSI."
echo "Done."
