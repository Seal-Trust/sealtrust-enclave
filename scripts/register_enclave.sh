#!/bin/bash
# Copyright (c), SealTrust
# SPDX-License-Identifier: Apache-2.0
#
# SealTrust Nautilus - Register Enclave On-Chain
# This script registers the enclave on Sui blockchain using attestation

set -e

# Check if all arguments are provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <enclave_package_id> <app_package_id> <enclave_config_id> <enclave_url> <module_name> <otw_name>"
    echo ""
    echo "Example:"
    echo "  $0 \\"
    echo "    0x0ff344b5b6f07b79b56a4ce1e9b1ef5a96ba219f6e6f2c49f194dee29dfc8b7f \\"
    echo "    0x... \\"
    echo "    0x... \\"
    echo "    http://3.88.45.123:3000 \\"
    echo "    sealtrust \\"
    echo "    SEALTRUST"
    echo ""
    echo "Parameters:"
    echo "  enclave_package_id  - Enclave Move package ID (deployed)"
    echo "  app_package_id      - SealTrust verification package ID"
    echo "  enclave_config_id   - EnclaveConfig object ID (from init)"
    echo "  enclave_url         - Public URL of your enclave"
    echo "  module_name         - Move module name (usually 'sealtrust')"
    echo "  otw_name            - One-time witness name (usually 'SEALTRUST')"
    exit 1
fi

ENCLAVE_PACKAGE_ID=$1
APP_PACKAGE_ID=$2
ENCLAVE_CONFIG_OBJECT_ID=$3
ENCLAVE_URL=$4
MODULE_NAME=$5
OTW_NAME=$6

echo "═══════════════════════════════════════════════════════"
echo "  SealTrust Nautilus - On-Chain Registration"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Parameters:"
echo "  Enclave Package:  $ENCLAVE_PACKAGE_ID"
echo "  App Package:      $APP_PACKAGE_ID"
echo "  Config Object:    $ENCLAVE_CONFIG_OBJECT_ID"
echo "  Enclave URL:      $ENCLAVE_URL"
echo "  Module:           $MODULE_NAME"
echo "  OTW:              $OTW_NAME"
echo ""

# Fetch attestation from enclave
echo "📡 Fetching attestation from enclave..."
ATTESTATION_HEX=$(curl -s $ENCLAVE_URL/get_attestation | jq -r '.attestation')

echo "✅ Got attestation (length=${#ATTESTATION_HEX})"

if [ ${#ATTESTATION_HEX} -eq 0 ]; then
    echo "❌ Error: Attestation is empty."
    echo "Please check:"
    echo "  1. Enclave is running: make -f Makefile.aws run"
    echo "  2. Enclave is exposed: ./expose_enclave.sh"
    echo "  3. URL is correct: $ENCLAVE_URL"
    echo "  4. /get_attestation endpoint exists"
    exit 1
fi

# Convert hex to vector array using Python
echo "🔄 Converting attestation to vector format..."
ATTESTATION_ARRAY=$(python3 - <<EOF
import sys

def hex_to_vector(hex_string):
    byte_values = [str(int(hex_string[i:i+2], 16)) for i in range(0, len(hex_string), 2)]
    rust_array = [f"{byte}u8" for byte in byte_values]
    return f"[{', '.join(rust_array)}]"

print(hex_to_vector("$ATTESTATION_HEX"))
EOF
)

echo "✅ Attestation converted"

# Execute sui client command
echo "🚀 Registering enclave on Sui blockchain..."
sui client ptb --assign v "vector$ATTESTATION_ARRAY" \
    --move-call "0x2::nitro_attestation::load_nitro_attestation" v @0x6 \
    --assign result \
    --move-call "${ENCLAVE_PACKAGE_ID}::enclave::register_enclave<${APP_PACKAGE_ID}::${MODULE_NAME}::${OTW_NAME}>" @${ENCLAVE_CONFIG_OBJECT_ID} result \
    --gas-budget 100000000

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ Enclave Registered Successfully!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Note the Enclave object ID from transaction output"
echo "  2. Update frontend CONFIG.ENCLAVE_OBJECT_ID"
echo "  3. Deploy frontend or test locally"
echo "═══════════════════════════════════════════════════════"
