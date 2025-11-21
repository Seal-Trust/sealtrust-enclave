#!/bin/bash
# Nautilus Enclave - Quick Setup Script
# Usage: ./setup.sh

set -e

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  Nautilus Enclave - Quick Setup        ║"
echo "║  TruthMarket TEE Verification          ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp .env.example .env
    echo ""
    echo "✅ .env created!"
    echo ""
    echo "⚡ READY FOR LOCAL TESTING"
    echo "   Run: ./setup.sh again to start the server"
    echo ""
    exit 0
fi

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust is not installed!"
    echo ""
    echo "Install Rust:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo ""
    exit 1
fi

# Check if Docker is running (optional for local dev)
if ! docker info > /dev/null 2>&1; then
    echo "⚠️  Docker is not running (optional for local dev)"
    echo "   You can either:"
    echo "   1. Start Docker and run: ./setup.sh"
    echo "   2. Or run directly with Rust: cargo run --release"
    echo ""
fi

echo "🚀 Running automated setup..."
echo ""

# Run the main setup script
./scripts/setup-local.sh
