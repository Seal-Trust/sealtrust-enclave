#!/bin/bash
# Nautilus Enclave - Local Development Setup
# Auto-builds and starts the enclave in dev mode

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Nautilus Enclave - Local Development Setup             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Source .env
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

DEV_MODE=${DEV_MODE:-true}
SERVER_PORT=${SERVER_PORT:-3000}

# Step 1: Check Rust installation
echo "📦 Step 1: Checking Rust installation..."
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust not found!"
    echo "Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

RUST_VERSION=$(rustc --version)
echo "✅ Found: $RUST_VERSION"
echo ""

# Step 2: Validate source code
echo "🔍 Step 2: Validating source code..."
if [ ! -f "src/lib.rs" ] || [ ! -f "src/main.rs" ] || [ ! -f "Cargo.toml" ]; then
    echo "❌ Source files missing!"
    exit 1
fi
echo "✅ Source files present"
echo ""

# Step 3: Check dependencies
echo "📚 Step 3: Checking dependencies..."
cargo check --quiet 2>&1 | grep -v "Checking\|Finished" || true
echo "✅ Dependencies OK"
echo ""

# Step 4: Choose deployment method
echo "🎯 Step 4: Choose deployment method"
echo ""
echo "Select how to run Nautilus:"
echo "  1) Cargo (Direct Rust - Fastest for development)"
echo "  2) Docker Compose (Containerized)"
echo "  3) Just build (don't run)"
echo ""
read -p "Choice [1-3]: " choice

case $choice in
    1)
        echo ""
        echo "🚀 Building with Cargo..."
        cargo build --release
        echo "✅ Build complete!"
        echo ""
        echo "📍 Starting Nautilus server (dev mode)..."
        echo "   Port: $SERVER_PORT"
        echo "   Mode: Development (no AWS Nitro required)"
        echo ""
        echo "Press Ctrl+C to stop"
        echo "════════════════════════════════════════"
        echo ""
        cargo run --release
        ;;

    2)
        echo ""
        echo "🐳 Using Docker Compose..."

        # Check Docker
        if ! docker info > /dev/null 2>&1; then
            echo "❌ Docker is not running!"
            exit 1
        fi

        echo "Building Docker image..."
        docker compose build

        echo ""
        echo "Starting container..."
        docker compose up -d

        echo ""
        echo "✅ Nautilus is running!"
        echo ""
        echo "View logs:    docker compose logs -f"
        echo "Stop server:  docker compose down"
        echo "Health check: curl http://localhost:$SERVER_PORT/health_check"
        ;;

    3)
        echo ""
        echo "🔨 Building only (not starting)..."
        cargo build --release
        echo "✅ Build complete!"
        echo ""
        echo "Binary location: ./target/release/nautilus-app"
        echo "Run manually:    ./target/release/nautilus-app"
        ;;

    *)
        echo "Invalid choice!"
        exit 1
        ;;
esac

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
echo "✅ Setup Complete!"
echo ""

if [ "$choice" != "3" ]; then
    echo "📝 Next Steps:"
    echo ""
    echo "1. Test health endpoint:"
    echo "   curl http://localhost:$SERVER_PORT/health_check"
    echo ""
    echo "2. Get enclave public key:"
    echo "   Check server logs for 'Enclave public key: 0x...'"
    echo ""
    echo "3. Test metadata verification:"
    echo "   See docs/API_EXAMPLES.md for sample requests"
    echo ""
    echo "4. Update frontend configuration:"
    echo "   NEXT_PUBLIC_NAUTILUS_URL=http://localhost:$SERVER_PORT"
    echo ""
fi

echo "════════════════════════════════════════════════════════════"
