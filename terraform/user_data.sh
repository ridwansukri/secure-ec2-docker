#!/bin/bash
# Secure EC2 Setup with Docker Compose
# NOTE: This script is designed to be resilient to transient network issues during first-boot.
set -euo pipefail

# Variables
LOG_FILE="/var/log/user-data-setup.log"
DOCKER_COMPOSE_VERSION="${docker_compose_version}"
# Region is injected by Terraform. Fallback to IMDSv2 if not provided.
AWS_REGION="${region}"
if [ -z "$AWS_REGION" ]; then
  # Fetch IMDSv2 token and then query region securely
  TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
  if [ -n "$TOKEN" ]; then
    AWS_REGION=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region || true)
  fi
fi

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Retry helper: retry CMD up to N times with backoff
retry() {
  local attempts=$${1:-5}; shift || true
  local delay=$${1:-5}; shift || true
  local n=1
  while true; do
    "$@" && break || {
      if [ $n -lt $attempts ]; then
        log "Command failed (attempt $n/$attempts): $* — retrying in $${delay}s"
        sleep "$delay"
        n=$((n+1))
      else
        log "Command failed after $${attempts} attempts: $*"
        return 1
      fi
    }
  done
}

log "Starting secure EC2 setup..."

# Update system packages (tolerate transient repo/NAT readiness)
log "Updating system packages..."
retry 10 6 yum update -y || log "Warning: yum update failed after retries — continuing"

# Install required packages
log "Installing required packages..."
retry 10 6 yum install -y \
  yum-utils \
  device-mapper-persistent-data \
  lvm2 \
  awscli \
  htop \
  curl \
  wget \
  unzip \
  amazon-cloudwatch-agent || log "Warning: base package install failed after retries"

# Install Docker
log "Installing Docker..."
# Prefer amazon-linux-extras on AL2 for docker engine; fallback to yum if extras is unavailable.
if command -v amazon-linux-extras >/dev/null 2>&1; then
  amazon-linux-extras enable docker || log "amazon-linux-extras enable docker failed"
  yum clean metadata || true
fi
retry 10 6 yum install -y docker || log "ERROR: Docker installation failed"
systemctl start docker || log "ERROR: failed to start docker service"
systemctl enable docker || true
usermod -aG docker ec2-user || true

# Install Docker Compose
log "Installing Docker Compose..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
-o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Verify Docker Compose installation
docker compose version || log "Warning: Docker compose version check failed"

# Configure Docker daemon
log "Configuring Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "live-restore": true,
  "userland-proxy": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker

# Create CloudWatch log groups
log "Creating CloudWatch log groups..."
aws logs create-log-group --log-group-name "/aws/ec2/messages" --region $AWS_REGION || true
aws logs create-log-group --log-group-name "/aws/ec2/secure" --region $AWS_REGION || true
aws logs create-log-group --log-group-name "/aws/ec2/docker" --region $AWS_REGION || true

# Configure CloudWatch Agent
log "Configuring CloudWatch Agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
"agent": {
"metrics_collection_interval": 60,
"run_as_user": "cwagent"
},
"metrics": {
"namespace": "CWAgent",
"metrics_collected": {
"cpu": {
"measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
"metrics_collection_interval": 60
},
"disk": {
"measurement": ["used_percent"],
"metrics_collection_interval": 60,
"resources": ["*"]
},
"mem": {
"measurement": ["mem_used_percent"],
"metrics_collection_interval": 60
}
}
},
"logs": {
"logs_collected": {
"files": {
"collect_list": [
{
"file_path": "/var/log/messages",
"log_group_name": "/aws/ec2/messages",
"log_stream_name": "{instance_id}"
}
]
}
}
}
}
EOF

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config \
-m ec2 \
-s \
-c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Setup application directory
log "Setting up application directory..."
mkdir -p /opt/app
chown ec2-user:ec2-user /opt/app
chmod 755 /opt/app

# Create sample docker-compose.yml
cat > /opt/app/docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    container_name: secure-web
    ports:
      - "80:80"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /var/cache/nginx:noexec,nosuid,size=100m
      - /var/run:noexec,nosuid,size=100m
      - /tmp:noexec,nosuid,size=100m

  app:
    image: node:alpine
    container_name: secure-app
    working_dir: /app
    ports:
      - "3000:3000"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
    user: "1000:1000"
EOF

chown ec2-user:ec2-user /opt/app/docker-compose.yml

log "EC2 setup completed successfully!"

