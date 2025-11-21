#!/bin/bash
# Copyright (c), TruthMarket
# SPDX-License-Identifier: Apache-2.0
#
# TruthMarket Nautilus - Expose Enclave
# This script runs on the AWS EC2 instance (parent) and:
# - Gets the running enclave's CID
# - Sends empty secrets.json to enclave via VSOCK
# - Exposes enclave port 3000 to the internet via socat

set -e

echo "🔌 Exposing TruthMarket Nautilus enclave to the internet..."

# Get the enclave ID and CID
# Expects there to be only one enclave running
ENCLAVE_ID=$(nitro-cli describe-enclaves | jq -r ".[0].EnclaveID")
ENCLAVE_CID=$(nitro-cli describe-enclaves | jq -r ".[0].EnclaveCID")

if [ -z "$ENCLAVE_ID" ] || [ "$ENCLAVE_ID" = "null" ]; then
    echo "❌ Error: No enclave running!"
    echo "Please start the enclave first:"
    echo "  make -f Makefile.aws run"
    exit 1
fi

echo "✅ Found enclave:"
echo "   ID:  $ENCLAVE_ID"
echo "   CID: $ENCLAVE_CID"

sleep 5

# Send secrets.json to enclave via VSOCK port 7777
# TruthMarket doesn't use external APIs, so we send empty JSON
echo "📦 Sending secrets.json to enclave..."
echo '{}' > secrets.json
cat secrets.json | socat - VSOCK-CONNECT:$ENCLAVE_CID:7777

echo "✅ Secrets sent to enclave"

# Expose enclave port 3000 to the internet
echo "🌐 Exposing port 3000 to the internet..."
socat TCP4-LISTEN:3000,reuseaddr,fork VSOCK-CONNECT:$ENCLAVE_CID:3000 &

SOCAT_PID=$!
echo "✅ Enclave exposed on port 3000 (socat PID: $SOCAT_PID)"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ TruthMarket Nautilus is now accessible!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Test the enclave:"
echo "  curl http://localhost:3000/health"
echo "  curl http://<PUBLIC_IP>:3000/health"
echo ""
echo "To stop the proxy:"
echo "  kill $SOCAT_PID"
echo ""
echo "Next step: Register enclave on-chain"
echo "  ./register_enclave.sh"
echo "═══════════════════════════════════════════════════════"
