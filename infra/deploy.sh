#!/bin/bash

set -e

echo "========== SETUP =========="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

PORT=3030
KEY_PATH="$SCRIPT_DIR/kv-node-key.pem"

PUBLIC_IP_FILE="$SCRIPT_DIR/public_ips.txt"
PRIVATE_IP_FILE="$SCRIPT_DIR/private_ips.txt"
SQS_FILE="$SCRIPT_DIR/sqs_urls.txt"
SNS_FILE="$SCRIPT_DIR/sns_topic.txt"
AWS_ENV_FILE="$SCRIPT_DIR/aws.env"

# -------- VALIDATION --------
[ ! -f "$KEY_PATH" ] && echo "Missing key.pem" && exit 1
[ ! -f "$PUBLIC_IP_FILE" ] && echo "Missing public_ips.txt" && exit 1
[ ! -f "$PRIVATE_IP_FILE" ] && echo "Missing private_ips.txt" && exit 1
[ ! -f "$SQS_FILE" ] && echo "Missing sqs_urls.txt" && exit 1
[ ! -f "$SNS_FILE" ] && echo "Missing sns_topic.txt" && exit 1
[ ! -f "$AWS_ENV_FILE" ] && echo "Missing aws.env" && exit 1

echo "========== LOAD CONFIG =========="

# Read IPs
PUBLIC_IPS=()
while IFS= read -r line || [ -n "$line" ]; do
  PUBLIC_IPS+=("$line")
done < "$PUBLIC_IP_FILE"

PRIVATE_IPS=()
while IFS= read -r line || [ -n "$line" ]; do
  PRIVATE_IPS+=("$line")
done < "$PRIVATE_IP_FILE"

SQS_URLS=()
while IFS= read -r line || [ -n "$line" ]; do
  SQS_URLS+=("$line")
done < "$SQS_FILE"

SNS_TOPIC_ARN=$(cat "$SNS_FILE")

echo "Nodes: ${#PUBLIC_IPS[@]}"

# -------- BUILD DOCKER --------
echo "========== BUILD DOCKER =========="

docker build --platform linux/amd64 -t kv-node .
docker save kv-node -o kv-node.tar

# -------- CLUSTER --------
echo "========== CLUSTER =========="

NODE_LIST=$(paste -sd "," "$PRIVATE_IP_FILE")
echo "$NODE_LIST"

# -------- DEPLOY --------
echo "========== DEPLOY =========="

FAILURES=0

for i in "${!PUBLIC_IPS[@]}"; do

  PUBLIC_IP=${PUBLIC_IPS[$i]}
  PRIVATE_IP=${PRIVATE_IPS[$i]}
  SQS_URL=${SQS_URLS[$i]}

  echo "---- Deploying $PUBLIC_IP ----"

  # Upload files
  scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY_PATH" kv-node.tar ubuntu@$PUBLIC_IP:/tmp/
  scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY_PATH" "$AWS_ENV_FILE" ubuntu@$PUBLIC_IP:/tmp/aws.env

  # Remote execution
  if ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@$PUBLIC_IP <<EOF
set -e

echo "========== REMOTE ($PRIVATE_IP) =========="

# Install Docker if needed
if ! command -v docker >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y docker.io
fi

sudo systemctl enable docker
sudo systemctl start docker

# Persistence
sudo mkdir -p /home/ubuntu/kv-data

# Load image
sudo docker load -i /tmp/kv-node.tar

# Restart container
sudo docker rm -f kv-node || true

echo "Starting container..."

sudo docker run -d \
  --name kv-node \
  -p 3030:3030 \
  -v /home/ubuntu/kv-data:/app/data \
  --env-file /tmp/aws.env \
  -e NODE_LIST="$NODE_LIST" \
  -e MY_IP="$PRIVATE_IP" \
  -e SNS_TOPIC_ARN="$SNS_TOPIC_ARN" \
  -e SQS_QUEUE_URL="$SQS_URL" \
  kv-node

sleep 5

echo "Checking health..."

curl -f http://localhost:3030/health

EOF
  then
    echo "SUCCESS: $PUBLIC_IP"
  else
    echo "FAILED: $PUBLIC_IP"
    FAILURES=$((FAILURES+1))
  fi

done

# -------- VERIFY --------
echo "========== VERIFY =========="

for ip in "${PUBLIC_IPS[@]}"; do
  echo -n "$ip → "
  if curl -s --max-time 2 http://$ip:$PORT/health >/dev/null; then
    echo "OK"
  else
    echo "FAIL"
  fi
done

# -------- RESULT --------
echo "========== RESULT =========="

if [ "$FAILURES" -gt 0 ]; then
  echo "Deployment failed ($FAILURES nodes)"
  exit 1
else
  echo "All nodes running"
fi