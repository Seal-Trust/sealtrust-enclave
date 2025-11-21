# Getting Started - Nautilus Enclave

**Local testing in 2 simple steps - NO AWS needed!**

---

## ⚡ Quick Start (Local Development)

```bash
# 1. Navigate to directory
cd nautilus-app

# 2. Run setup
./setup.sh

# That's it! Nautilus will be running on localhost:3000
```

---

## 🎯 What You'll Get

✅ **Local development mode** - Test WITHOUT AWS Nitro Enclave
✅ **Metadata verification** - Real cryptographic signatures
✅ **Docker support** - Containerized or direct Rust
✅ **Health monitoring** - Auto health checks
✅ **Hot reload** - Fast development cycle
✅ **Production ready** - Same code for AWS deployment

---

## 📋 Prerequisites

### Required

- ✅ Rust installed (1.75+)
- ✅ Git (should already have)

### Optional

- ✅ Docker & Docker Compose (for containerized testing)

### Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Verify
cargo --version
rustc --version
```

---

## 🚀 Step-by-Step Guide

### Step 1: Setup Environment

```bash
cd nautilus-app

# Create .env file
./setup.sh

# This creates .env with development defaults
# No editing needed for local testing!
```

### Step 2: Start Server

```bash
# Run setup again to start
./setup.sh

# Choose option 1 (Cargo) or 2 (Docker)
# Option 1 is faster for development
```

**Expected output:**

```
Nautilus server listening on 127.0.0.1:3000
Enclave public key: 0xabc123...
Ready to accept requests
```

**⚠️ SAVE THE PUBLIC KEY!** You'll need it later.

### Step 3: Test It Works

```bash
# In another terminal

# Health check
curl http://localhost:3000/health_check
# Expected: "OK"

# Test metadata verification
curl -X POST http://localhost:3000/verify_metadata \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": {
      "dataset_id": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32],
      "name": [116,101,115,116],
      "description": [116,101,115,116,32,100,97,116,97,115,101,116],
      "format": [67,83,86],
      "size": 1024,
      "original_hash": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31],
      "walrus_blob_id": [98,108,111,98],
      "seal_policy_id": [112,111,108],
      "timestamp": 1700000000,
      "uploader": [117,115,101,114]
    }
  }'

# Should return JSON with "signature" and "enclave_public_key"
```

---

## 🛠️ Common Commands

### Using Cargo (Direct Rust)

```bash
# Build only
cargo build --release

# Run (with logs)
RUST_LOG=debug cargo run --release

# Run in background
cargo run --release &

# Stop
pkill nautilus-app
```

### Using Docker Compose

```bash
# Build image
docker compose build

# Start container
docker compose up -d

# View logs
docker compose logs -f

# Stop container
docker compose down

# Restart
docker compose restart

# Rebuild and restart
docker compose build && docker compose up -d
```

---

## 🔍 Development vs Production

| Aspect | Development (Your Mac) | Production (AWS) |
|--------|------------------------|------------------|
| **Hardware** | Regular CPU | AWS Nitro Enclave |
| **Attestation** | Simulated | Real hardware proof |
| **Key Storage** | File (.enclave_key.json) | Enclave memory (ephemeral) |
| **Performance** | Fast compilation | Requires .eif build |
| **Testing** | Instant feedback | Need EC2 instance |
| **Cost** | Free | ~$140/month |

**The code is IDENTICAL** - switching between dev and production is just changing `DEV_MODE`!

---

## 📊 How It Works

### Local Development Mode

```
Your Mac
├─ Rust Binary (nautilus-app)
│  ├─ HTTP Server (Axum)
│  ├─ Ed25519 Signing
│  ├─ BCS Serialization
│  └─ Key from .enclave_key.json
└─ Port 3000 (direct access)
```

### Production AWS Mode

```
AWS EC2
├─ Nitro Enclave (isolated CPU/memory)
│  ├─ Nautilus Binary (.eif)
│  ├─ Hardware Attestation
│  ├─ Ephemeral Key (enclave-only)
│  └─ vsock socket
├─ vsock Proxy
│  └─ Converts vsock ↔ TCP
└─ Port 3000 → Internet
```

---

## 🎓 Understanding the Code

### Project Structure

```
nautilus-app/
├── src/
│   ├── main.rs          # HTTP server (Axum)
│   ├── lib.rs           # Verification logic
│   └── common.rs        # Ed25519 crypto
├── Cargo.toml           # Dependencies
├── .env                 # Configuration
├── setup.sh             # Quick setup
├── docker-compose.yml   # Local container
├── Dockerfile.dev       # Dev Docker image
└── allowed_endpoints.yaml  # Network whitelist
```

### Key Files

**src/lib.rs** - Metadata verification:
```rust
pub struct DatasetVerification {
    pub dataset_id: Vec<u8>,
    pub name: Vec<u8>,
    pub description: Vec<u8>,
    pub format: Vec<u8>,
    pub size: u64,
    pub original_hash: Vec<u8>,
    pub walrus_blob_id: Vec<u8>,
    pub seal_policy_id: Vec<u8>,
    pub timestamp: u64,
    pub uploader: Vec<u8>,
}
```

**src/common.rs** - Signing:
```rust
pub fn sign_metadata(metadata: &DatasetVerification, private_key: &Ed25519PrivateKey)
    -> Vec<u8>
```

---

## 🐛 Troubleshooting

### "Rust not found"

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### "Address already in use"

```bash
# Port 3000 is taken
lsof -ti:3000 | xargs kill

# Or change port in .env
SERVER_PORT=3001
```

### "Docker not running"

```bash
# Option 1: Start Docker Desktop
# Option 2: Use Cargo instead
./setup.sh
# Choose option 1 (Cargo)
```

### "Compilation failed"

```bash
# Update dependencies
cargo clean
cargo update
cargo build --release
```

### "Can't connect from frontend"

```bash
# Check CORS in .env
CORS_ORIGINS=http://localhost:3001,http://localhost:3000

# Restart after changing .env
docker compose restart
# OR
cargo run --release
```

---

## 🚀 AWS Deployment (Later)

When ready to deploy to production:

1. **See README.md** - Full AWS deployment guide
2. **Set DEV_MODE=false** in .env
3. **Build .eif** - Enclave Image Format
4. **Deploy to EC2** with Nitro Enclaves enabled
5. **Setup vsock proxy** for network communication
6. **Configure systemd** for auto-restart

**For now:** Local testing is perfect! Deploy to AWS when you're ready.

---

## 📝 Next Steps

### Step 1: Get Public Key

```bash
# Start server
./setup.sh

# Look for this in logs:
# "Enclave public key: 0xabc123..."

# Or query endpoint:
curl http://localhost:3000/enclave_public_key
```

### Step 2: Update Move Contract

**File:** `move/truthmarket-verification/sources/truthmarket.move`

```move
// Update with your enclave's public key
const ENCLAVE_PUBLIC_KEY: vector<u8> = x"abc123...";
```

### Step 3: Update Frontend

**File:** `truthmarket-frontend-v3/.env.local`

```env
NEXT_PUBLIC_NAUTILUS_URL=http://localhost:3000
```

### Step 4: Test Integration

1. Register dataset in frontend
2. Frontend calls `/verify_metadata`
3. Nautilus returns signature
4. Move contract verifies signature
5. DatasetNFT minted on Sui

---

## ✅ Success Checklist

You're ready when:

- [ ] `./setup.sh` runs without errors
- [ ] `curl http://localhost:3000/health_check` returns "OK"
- [ ] Enclave public key logged at startup
- [ ] Test verification returns signature
- [ ] Frontend can connect to Nautilus
- [ ] Move contract has correct public key
- [ ] End-to-end test: register dataset works

---

## 💡 Pro Tips

### Fast Development Loop

```bash
# Terminal 1: Auto-restart on code changes
cargo watch -x 'run --release'

# Terminal 2: Test endpoint
curl http://localhost:3000/health_check
```

### View Detailed Logs

```bash
RUST_LOG=debug cargo run --release
```

### Test Different Scenarios

```bash
# Valid metadata
curl -X POST http://localhost:3000/verify_metadata -d @test_valid.json

# Invalid metadata (missing fields)
curl -X POST http://localhost:3000/verify_metadata -d @test_invalid.json

# Large metadata
curl -X POST http://localhost:3000/verify_metadata -d @test_large.json
```

### Performance Testing

```bash
# Install hey (HTTP load tester)
brew install hey

# Test performance
hey -n 1000 -c 10 http://localhost:3000/health_check
```

---

## 📞 Need Help?

- **Quick fix:** Check logs: `cargo run --release` or `docker compose logs`
- **Full guide:** See `README.md`
- **AWS deployment:** See `README.md` Step 1-11
- **API examples:** See `docs/API_EXAMPLES.md`

---

## 🎯 What Makes This Different?

### Traditional Verification
❌ Backend server (can be hacked)
❌ No proof of correctness
❌ Trust the operator

### Nautilus TEE
✅ Isolated hardware (tamper-proof)
✅ Cryptographic attestation
✅ Trust the math, not people

---

**Ready to start? Run: `./setup.sh`** 🚀

**Time to run:** ~2 minutes (first build ~5 minutes)

**What you get:** Production-grade verification on your laptop!
