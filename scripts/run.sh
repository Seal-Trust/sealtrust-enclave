#!/bin/sh
# Copyright (c), TruthMarket
# SPDX-License-Identifier: Apache-2.0
#
# TruthMarket Nautilus Enclave - Init Script
# This script runs inside the AWS Nitro Enclave and:
# - Sets up networking (loopback)
# - Waits for secrets.json from parent instance via VSOCK
# - Starts the Nautilus metadata verification server

set -e # Exit immediately if a command exits with a non-zero status

echo "🚀 TruthMarket Nautilus Enclave starting..."
export PYTHONPATH=/lib/python3.11:/usr/local/lib/python3.11/lib-dynload:/usr/local/lib/python3.11/site-packages:/lib
export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH

# Assign IP address to local loopback
echo "Setting up loopback interface..."
busybox ip addr add 127.0.0.1/32 dev lo
busybox ip link set dev lo up

# Add hosts record
echo "127.0.0.1   localhost" > /etc/hosts

# ENDPOINT CONFIGURATION BLOCK
# This will be populated by configure_enclave.sh during deployment
# Example:
# echo "127.0.0.64   aggregator.walrus-testnet.walrus.space" >> /etc/hosts


cat /etc/hosts

# Wait for secrets.json from parent instance (sent via VSOCK port 7777)
# Note: For TruthMarket, secrets.json is empty {} since we don't use external APIs
echo "Waiting for secrets.json from parent instance..."
JSON_RESPONSE=$(socat - VSOCK-LISTEN:7777,reuseaddr)

# Parse secrets and set as environment variables
echo "$JSON_RESPONSE" | jq -r 'to_entries[] | "\(.key)=\(.value)"' > /tmp/kvpairs
while IFS="=" read -r key value; do
    export "$key"="$value"
done < /tmp/kvpairs
rm -f /tmp/kvpairs

echo "✅ Environment configured"

# TRAFFIC FORWARDER BLOCK
# This will be populated by configure_enclave.sh during deployment
# Forwards traffic from 127.0.0.x -> Port 443 at CID 3 via vsock-proxy
# Example:
# python3 /traffic_forwarder.py 127.0.0.64 443 3 8101 &


# Listen on VSOCK Port 3000 and forward to localhost:3000
# This allows the parent instance to communicate with the enclave
echo "Setting up VSOCK listener on port 3000..."
socat VSOCK-LISTEN:3000,reuseaddr,fork TCP:localhost:3000 &

echo "🔐 Starting TruthMarket Nautilus server..."
/nautilus-server
