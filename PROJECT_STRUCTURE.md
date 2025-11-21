# Nautilus App - Project Structure

**Clean, organized structure for TruthMarket Nautilus enclave application**

---

## 📁 Directory Layout

```
nautilus-app/
├── src/                    # Rust source code
│   ├── main.rs            # HTTP server entry point
│   ├── lib.rs             # Core verification logic
│   └── common.rs          # Crypto & attestation utilities
│
├── scripts/               # Deployment & management scripts
│   ├── setup-aws.sh       # Launch AWS EC2 + Nitro Enclave
│   ├── setup-local.sh     # Local dev environment setup
│   ├── expose_enclave.sh  # Expose enclave to internet (vsock proxy)
│   ├── register_enclave.sh # Register on Sui blockchain
│   ├── run.sh             # Enclave init script (runs inside enclave)
│   └── setup.sh           # Generic setup helper
│
├── docker/                # Docker & container configs
│   ├── Containerfile.aws  # AWS Nitro enclave build (production)
│   ├── Dockerfile.dev     # Local development container
│   └── docker-compose.yml # Docker Compose for local dev
│
├── docs/                  # Documentation
│   ├── AWS_DEPLOYMENT.md          # Complete AWS deployment guide
│   ├── AWS_DEPLOYMENT_SUMMARY.md  # Quick AWS reference
│   ├── GETTING_STARTED.md         # Quick start guide
│   └── LOCAL_DEV_SETUP.md         # Local development setup
│
├── Cargo.toml             # Rust dependencies
├── Makefile.aws           # Build commands for AWS
├── allowed_endpoints.yaml # Network whitelist for enclave
├── README.md              # Main project documentation
└── PROJECT_STRUCTURE.md   # This file
```

---

## 🚀 Quick Start

### Local Development

```bash
# Option 1: Cargo (recommended)
cargo run --release

# Option 2: Docker Compose
cd docker
docker compose up

# Test it works
curl http://localhost:3000/health_check
```

### AWS Production Deployment

```bash
# 1. Setup EC2 instance
export KEY_PAIR=your-aws-key
cd scripts
./setup-aws.sh

# 2. On EC2 instance
make -f Makefile.aws build
make -f Makefile.aws run

# 3. Expose to internet
cd scripts
./expose_enclave.sh

# 4. Register on-chain
./register_enclave.sh <ENCLAVE_PKG> <APP_PKG> <CONFIG_ID> http://<IP>:3000 truthmarket TRUTHMARKET
```

---

## 📋 Scripts Reference

### `scripts/setup-aws.sh`
**Purpose:** Launch AWS EC2 instance with Nitro Enclaves enabled

**Requirements:**
- AWS CLI configured
- `KEY_PAIR` environment variable set

**Usage:**
```bash
export KEY_PAIR=my-aws-key
cd /path/to/nautilus-app
./scripts/setup-aws.sh
```

**What it does:**
1. Creates m5.xlarge EC2 instance
2. Installs Nitro CLI, Docker, dependencies
3. Configures security groups (ports 22, 443, 3000)
4. Sets up vsock-proxy for allowed endpoints
5. Returns PUBLIC_IP for access

---

### `scripts/expose_enclave.sh`
**Purpose:** Expose enclave HTTP server to internet

**Requirements:**
- Enclave must be running
- Run on EC2 instance (not locally)

**Usage:**
```bash
cd /path/to/nautilus-app
./scripts/expose_enclave.sh
```

**What it does:**
1. Gets running enclave CID
2. Sends secrets.json via VSOCK port 7777
3. Creates socat proxy: VSOCK → TCP port 3000
4. Makes enclave accessible from internet

---

### `scripts/register_enclave.sh`
**Purpose:** Register enclave on Sui blockchain with attestation

**Requirements:**
- Sui CLI configured
- Enclave running and exposed
- Move contracts deployed

**Usage:**
```bash
./scripts/register_enclave.sh \
  <ENCLAVE_PACKAGE_ID> \
  <APP_PACKAGE_ID> \
  <ENCLAVE_CONFIG_ID> \
  http://<PUBLIC_IP>:3000 \
  truthmarket \
  TRUTHMARKET
```

**What it does:**
1. Fetches attestation from `/get_attestation` endpoint
2. Converts hex attestation to vector format
3. Calls `register_enclave` on Sui
4. Creates `Enclave` object with public key

---

### `scripts/run.sh`
**Purpose:** Init script that runs inside enclave

**⚠️ WARNING:** This runs INSIDE the isolated enclave. Do NOT modify unless you understand enclave architecture!

**What it does:**
1. Sets up loopback networking
2. Waits for secrets.json from parent (VSOCK port 7777)
3. Configures /etc/hosts for allowed endpoints
4. Starts VSOCK listener on port 3000
5. Launches Nautilus server binary

---

## 🐳 Docker Reference

### `docker/Containerfile.aws`
**Purpose:** Build reproducible .eif file for AWS Nitro Enclaves

**Used by:** `Makefile.aws` build target

**Key features:**
- StageX images for deterministic builds
- Static linking (musl)
- Generates PCR measurements
- Creates .eif (Enclave Image Format)

**Output:**
- `out/nitro.eif` - Enclave image
- `out/nitro.pcrs` - PCR measurements

---

### `docker/Dockerfile.dev`
**Purpose:** Local development container

**Used by:** `docker-compose.yml`

**Features:**
- Hot reload (volume mounts)
- DEV_MODE enabled (no real attestation)
- Exposes port 3000

---

### `docker/docker-compose.yml`
**Purpose:** Docker Compose config for local dev

**Usage:**
```bash
cd docker
docker compose up
```

**Services:**
- `nautilus-dev` - Nautilus server in DEV_MODE

---

## 📚 Documentation Reference

### `docs/AWS_DEPLOYMENT.md`
Complete production deployment guide with:
- Step-by-step AWS setup
- Enclave build & deployment
- On-chain registration
- Monitoring & troubleshooting
- **10 detailed FAQs** (CPU/memory, domain setup, costs, etc.)

### `docs/AWS_DEPLOYMENT_SUMMARY.md`
Quick reference for:
- Files overview
- Quick start commands
- What each script does
- Verification steps

### `docs/GETTING_STARTED.md`
Quick start guide for developers:
- 5-minute setup
- Local testing
- Integration with frontend

### `docs/LOCAL_DEV_SETUP.md`
Local development guide:
- Prerequisites
- Running with Cargo
- Running with Docker
- Testing endpoints

---

## 🔧 Build Commands

### Local Development
```bash
# Cargo
cargo build --release
cargo run --release

# Docker
cd docker
docker compose build
docker compose up
```

### AWS Production
```bash
# Build .eif file
make -f Makefile.aws build

# Run enclave
make -f Makefile.aws run

# Run with debug console
make -f Makefile.aws run-debug

# View PCRs
make -f Makefile.aws pcrs

# Check status
make -f Makefile.aws status

# Clean build artifacts
make -f Makefile.aws clean
```

---

## 🔍 Common Tasks

### Start Local Dev Server
```bash
cargo run --release
```

### Test Metadata Verification
```bash
curl -X POST http://localhost:3000/verify_metadata \
  -H "Content-Type: application/json" \
  -d @test_metadata.json
```

### Deploy to AWS (Full Flow)
```bash
# 1. Launch EC2
export KEY_PAIR=my-key
./scripts/setup-aws.sh
# Note PUBLIC_IP from output

# 2. SSH to instance
ssh ec2-user@<PUBLIC_IP>

# 3. Clone repo
git clone <your-repo>
cd truthMarket/nautilus-app

# 4. Build & run
make -f Makefile.aws build
make -f Makefile.aws run
./scripts/expose_enclave.sh

# 5. Register on-chain
./scripts/register_enclave.sh ... http://<PUBLIC_IP>:3000 ...
```

### Update Running Enclave
```bash
# Stop old enclave
sudo nitro-cli terminate-enclave --enclave-id <ID>

# Rebuild
make -f Makefile.aws build

# Start new enclave
make -f Makefile.aws run
./scripts/expose_enclave.sh

# Re-register (new key!)
./scripts/register_enclave.sh ...
```

---

## 🚨 Important Notes

### Script Execution Context

**Run from nautilus-app root:**
```bash
# ✅ CORRECT
cd /path/to/nautilus-app
./scripts/setup-aws.sh

# ❌ WRONG
cd /path/to/nautilus-app/scripts
./setup-aws.sh  # Will fail (can't find allowed_endpoints.yaml)
```

**Exception:** Docker commands run from docker/ dir:
```bash
cd docker
docker compose up  # ✅ Correct
```

---

### Path Updates After Reorganization

**Scripts now use relative paths:**
- `../allowed_endpoints.yaml` (from scripts/)
- `scripts/run.sh` (referenced in setup-aws.sh)

**Docker files use parent context:**
- `context: ..` (parent directory)
- `dockerfile: docker/Dockerfile.dev`

**Documentation references updated:**
- All `./script.sh` → `./scripts/script.sh`

---

## 📞 Need Help?

1. **Local dev issues:** See `docs/LOCAL_DEV_SETUP.md`
2. **AWS deployment:** See `docs/AWS_DEPLOYMENT.md`
3. **Quick reference:** See `docs/AWS_DEPLOYMENT_SUMMARY.md`
4. **General questions:** See `README.md`

---

**Last Updated:** 2025-11-21 (Directory reorganization)
