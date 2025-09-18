#!/bin/bash
# Test script to validate URLs and configuration snippets used by user_data.sh
# This script is safe to run locally; it requires only curl. Optional checks use Python and Docker if available.

set -euo pipefail

echo "Testing Docker Compose download URL..."
curl -I "https://github.com/docker/compose/releases/download/v2.39.3/docker-compose-linux-x86_64" >/dev/null && echo "Compose URL reachable"

echo "Testing AWS CLI availability..."
if command -v aws >/dev/null 2>&1; then
  aws --version || true
  aws sts get-caller-identity >/dev/null 2>&1 && echo "AWS CLI works (get-caller-identity)" || echo "AWS CLI present but credentials not configured"
else
  echo "AWS CLI not found; skipping AWS checks"
fi

echo "Testing JSON syntax for CloudWatch config..."
cat > /tmp/test-cw-config.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool /tmp/test-cw-config.json >/dev/null && echo "CloudWatch JSON config is valid (python3)"
elif command -v python >/dev/null 2>&1; then
  python -m json.tool /tmp/test-cw-config.json >/dev/null && echo "CloudWatch JSON config is valid (python)"
elif command -v py >/dev/null 2>&1; then
  py -m json.tool /tmp/test-cw-config.json >/dev/null && echo "CloudWatch JSON config is valid (py)"
elif command -v jq >/dev/null 2>&1; then
  jq empty /tmp/test-cw-config.json && echo "CloudWatch JSON config is valid (jq)"
else
  echo "No JSON validator (python/jq) found; skipping JSON validation"
fi

echo "Testing Docker Compose YAML syntax..."
cat > /tmp/test-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    container_name: secure-web
    ports:
      - "80:80"
    restart: unless-stopped
EOF

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    docker compose -f /tmp/test-compose.yml config >/dev/null && echo "Docker Compose YAML is valid (docker compose)"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f /tmp/test-compose.yml config >/dev/null && echo "Docker Compose YAML is valid (docker-compose)"
  else
    echo "Docker found but compose plugin not installed; skipping compose validation"
  fi
else
  echo "Docker not found; skipping compose validation"
fi
