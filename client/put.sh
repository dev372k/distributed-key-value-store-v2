#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_FILE="$SCRIPT_DIR/../infra/public_ips.txt"

# -------- VALIDATION --------
if [[ ! -f "$IP_FILE" ]]; then
  echo "Error: public_ips.txt not found"
  exit 1
fi

# -------- PARSE ARGUMENTS --------
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --k) KEY="$2"; shift ;;
    --v) VALUE="$2"; shift ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# -------- INPUT CHECK --------
if [[ -z "$KEY" || -z "$VALUE" ]]; then
  echo "Usage: $0 --k <key> --v <value>"
  exit 1
fi

# -------- LOAD NODES --------
NODES=()
while IFS= read -r line || [ -n "$line" ]; do
  NODES+=("$line")
done < "$IP_FILE"

COUNT=${#NODES[@]}

if [[ $COUNT -eq 0 ]]; then
  echo "Error: No nodes found"
  exit 1
fi

# -------- CONSISTENT HASH --------
HASH=$(echo -n "$KEY" | sha1sum | awk '{print $1}')
NUM=$((16#${HASH:0:8}))
INDEX=$((NUM % COUNT))

TARGET_NODE=${NODES[$INDEX]}

# echo "Target node: $TARGET_NODE"

# -------- API CALL (MAPPING HAPPENS HERE) --------
curl -s "http://$TARGET_NODE:3030/put?key=$KEY&value=$VALUE"