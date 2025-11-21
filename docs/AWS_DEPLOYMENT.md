# TruthMarket Nautilus - AWS Nitro Enclave Deployment Guide

**Complete guide for deploying TruthMarket Nautilus to AWS Nitro Enclaves for production use**

---

## 📋 Prerequisites

### Required
- ✅ AWS Account with admin access
- ✅ AWS CLI installed and configured (`aws configure`)
- ✅ SSH key pair created in your AWS region
- ✅ Docker installed (for building .eif file)
- ✅ `yq` command-line YAML processor
  - macOS: `brew install yq`
  - Ubuntu: `sudo apt-get install yq`

### Optional but Recommended
- Sui CLI configured with your wallet
- Basic understanding of AWS EC2 and Nitro Enclaves

---

## 🏗️ Architecture Overview

### Production AWS Setup
```
Internet
    ↓
EC2 Instance (m5.xlarge)
    ├─ Docker (for building)
    ├─ Nitro CLI
    ├─ socat (vsock proxy)
    │
    └─ Nitro Enclave (isolated CPU/memory)
        ├─ Nautilus Binary
        ├─ Ephemeral Ed25519 Key
        ├─ Hardware Attestation
        └─ VSOCK Port 3000 → Internet
```

###Files Created

All AWS deployment files are in `nautilus-app/`:

```
nautilus-app/
├── Containerfile.aws      # Builds .eif file (Enclave Image Format)
├── Makefile.aws           # Build commands (make build, make run)
├── run.sh                 # Init script (runs inside enclave)
├── setup-aws.sh           # EC2 instance launcher
├── expose_enclave.sh      # Exposes enclave to internet
├── register_enclave.sh    # On-chain registration
├── allowed_endpoints.yaml # Network whitelist
└── AWS_DEPLOYMENT.md      # This file
```

---

## 🚀 Step-by-Step Deployment

### Phase 1: Local Preparation (Your Mac)

#### 1.1 Set AWS Credentials
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1  # Or your preferred region
```

#### 1.2 Configure SSH Key
```bash
# Use your existing SSH key pair name
export KEY_PAIR=my-aws-keypair  # IMPORTANT: Must already exist in AWS!
```

#### 1.3 Launch EC2 Instance
```bash
cd /Users/apple/dev/hackathon/haluout/truthMarket/nautilus-app

# Launch instance with Nitro Enclaves enabled
./scripts/setup-aws.sh
```

**What this does:**
- Creates m5.xlarge EC2 instance ($0.192/hour)
- Enables Nitro Enclaves
- Configures security groups (ports 22, 443, 3000)
- Installs Docker, Nitro CLI, and dependencies
- Returns PUBLIC_IP address

**Expected output:**
```
═══════════════════════════════════════════════════════
✅ AWS EC2 Instance Configured Successfully!
═══════════════════════════════════════════════════════

Instance Details:
  Name:       truthmarket-nautilus-123456
  ID:         i-0abcd1234
  Public IP:  3.88.45.123
  Region:     us-east-1
  Type:       m5.xlarge (Nitro Enclaves enabled)
```

**Save the PUBLIC_IP** - you'll need it!

---

### Phase 2: Build Enclave (On EC2 Instance)

#### 2.1 SSH into EC2 Instance
```bash
# Wait 2-3 minutes for initialization
ssh ec2-user@<PUBLIC_IP>
```

#### 2.2 Clone Your Repository
```bash
cd ~
git clone https://github.com/your-username/truthMarket.git
cd truthMarket/nautilus-app
```

#### 2.3 Build Enclave Image
```bash
# Build .eif file (takes 10-15 minutes first time)
make -f Makefile.aws build
```

**What this does:**
- Builds Rust binary with static linking
- Creates reproducible enclave image
- Generates .eif file and PCR measurements
- Outputs to `out/nitro.eif`

**Expected output:**
```
✅ Enclave image built: out/enclaveos.tar
✅ Enclave .eif file ready: out/nitro.eif
✅ PCR measurements saved: out/nitro.pcrs
```

#### 2.4 View PCR Measurements (Optional)
```bash
make -f Makefile.aws pcrs
```

These PCR values will be used in EnclaveConfig on-chain.

---

### Phase 3: Run Enclave

#### 3.1 Start the Enclave
```bash
make -f Makefile.aws run
```

**What this does:**
- Allocates 512MB memory and 2 CPU cores
- Loads `.eif` file into Nitro Enclave
- Starts isolated execution
- Returns Enclave ID and CID

**Expected output:**
```
Start allocating memory...
Started enclave with enclave-id: i-0abc123-enc17f8..., cpu-ids: [1, 3], memory: 512 MiB
✅ Enclave started
```

#### 3.2 Verify Enclave is Running
```bash
sudo nitro-cli describe-enclaves
```

**Expected output:**
```json
[
  {
    "EnclaveID": "i-0abc123-enc17f8...",
    "EnclaveCID": 16,
    "NumberOfCPUs": 2,
    "CPUIDs": [1, 3],
    "MemoryMiB": 512,
    "State": "RUNNING",
    "Flags": "NONE"
  }
]
```

---

### Phase 4: Expose to Internet

#### 4.1 Run Expose Script
```bash
./scripts/expose_enclave.sh
```

**What this does:**
- Sends empty `secrets.json` to enclave via VSOCK
- Creates socat proxy: VSOCK port 3000 → TCP port 3000
- Makes enclave accessible from internet

**Expected output:**
```
═══════════════════════════════════════════════════════
✅ TruthMarket Nautilus is now accessible!
═══════════════════════════════════════════════════════

Test the enclave:
  curl http://localhost:3000/health
  curl http://<PUBLIC_IP>:3000/health
```

#### 4.2 Test Locally
```bash
curl http://localhost:3000/health
# Expected: OK

curl http://localhost:3000/get_attestation | jq
# Expected: JSON with attestation document
```

#### 4.3 Test from Internet
```bash
# From your Mac
curl http://<PUBLIC_IP>:3000/health
```

If this works, your enclave is live! 🎉

---

### Phase 5: On-Chain Registration

#### 5.1 Prerequisites
Before registering, you need:

1. **EnclaveConfig object** - Created during Move package init
   ```bash
   # On your Mac, after deploying Move contracts:
   sui client call \
     --package <ENCLAVE_PACKAGE_ID> \
     --module enclave \
     --function init \
     --args ... \
     --gas-budget 100000000

   # Note the EnclaveConfig object ID
   ```

2. **Package IDs** - From Move deployment
   - `ENCLAVE_PACKAGE_ID` - Enclave package
   - `APP_PACKAGE_ID` - TruthMarket verification package

3. **Public IP** - From Phase 1

#### 5.2 Register Enclave
```bash
# On EC2 instance
./scripts/register_enclave.sh \
  0x0ff344b5b6f07b79b56a4ce1e9b1ef5a96ba219f6e6f2c49f194dee29dfc8b7f \  # Enclave package
  0x<APP_PACKAGE_ID> \                                                      # Your app package
  0x<ENCLAVE_CONFIG_OBJECT_ID> \                                           # Config object
  http://<PUBLIC_IP>:3000 \                                                 # Your enclave URL
  truthmarket \                                                             # Module name
  TRUTHMARKET                                                               # OTW name
```

**What this does:**
1. Calls `/get_attestation` endpoint
2. Converts hex attestation to vector format
3. Calls `register_enclave` on Sui
4. Creates `Enclave` object with public key

**Expected output:**
```
═══════════════════════════════════════════════════════
✅ Enclave Registered Successfully!
═══════════════════════════════════════════════════════

Transaction Digest: ABC123...
Created Objects:
  - Enclave object: 0xdef456...
```

**IMPORTANT: Save the Enclave object ID!**

---

### Phase 6: Update Frontend

#### 6.1 Update Constants
```typescript
// truthmarket-frontend-v3/src/lib/constants.ts
export const CONFIG = {
  // ...
  NAUTILUS_URL: "http://<PUBLIC_IP>:3000",  // Your AWS enclave
  ENCLAVE_OBJECT_ID: "0x<ENCLAVE_ID>",      // From Phase 5
  // ...
};
```

#### 6.2 Update Registration Hook
```typescript
// truthmarket-frontend-v3/src/hooks/useTruthMarket.ts
// Change from register_dataset_dev to register_dataset
const [nft] = tx.moveCall({
  target: `${CONFIG.VERIFICATION_PACKAGE}::truthmarket::register_dataset`,  // No longer _dev!
  arguments: [
    // ... all metadata ...
    tx.object(CONFIG.ENCLAVE_OBJECT_ID),  // Use Enclave, not EnclaveConfig!
  ],
});
```

#### 6.3 Test End-to-End
```bash
cd truthmarket-frontend-v3
pnpm dev

# Register a dataset
# Should now use REAL signature verification!
```

---

## 🔒 Security Considerations

### ✅ Production-Ready Features
- **Hardware Isolation**: Nitro Enclave provides CPU/memory isolation
- **Ephemeral Keys**: Generated inside enclave, never leaves
- **Attestation**: PCR measurements prove code integrity
- **Signature Verification**: On-chain verification of TEE signatures

### ⚠️ Important Notes
1. **PCR Updates**: If you change code, PCRs change → must update EnclaveConfig
2. **No Debug Mode**: Never use `--debug-mode` in production
3. **Network Isolation**: Enclave has no internet except vsock proxy
4. **Key Rotation**: Each enclave restart = new ephemeral key

---

## 💰 Cost Estimate

### AWS Costs (us-east-1)
- **m5.xlarge**: $0.192/hour × 730 hours = $140/month
- **EBS Storage (200GB)**: $20/month
- **Data Transfer**: ~$10/month
- **Total**: ~$170/month

### Cost Optimization
- Use Reserved Instances: Save up to 60%
- Use Spot Instances: NOT recommended (enclave restart = new key)
- Smaller instance: m5.large works but less performant

---

## 🐛 Troubleshooting

### Problem: Enclave won't start
```bash
# Check Nitro CLI
sudo nitro-cli describe-enclaves

# Check allocator
sudo systemctl status nitro-enclaves-allocator

# View logs
sudo nitro-cli console --enclave-id <ENCLAVE_ID>
```

### Problem: Can't access from internet
```bash
# Check security group
aws ec2 describe-security-groups --group-names truthmarket-nautilus-sg

# Check socat is running
ps aux | grep socat

# Restart expose script
./scripts/expose_enclave.sh
```

### Problem: Attestation fails
```bash
# Check enclave is running
sudo nitro-cli describe-enclaves

# Test endpoint locally
curl http://localhost:3000/get_attestation

# Check PCR measurements match
cat out/nitro.pcrs
```

### Problem: Signature verification fails on-chain
- **Cause**: Enclave object not created or wrong ID
- **Fix**: Re-run `register_enclave.sh` with correct parameters
- **Verify**: Check Enclave object exists on Sui Explorer

---

## 📊 Monitoring

### Health Checks
```bash
# From EC2 instance
watch -n 5 'curl -s http://localhost:3000/health'

# From outside
watch -n 5 'curl -s http://<PUBLIC_IP>:3000/health'
```

### Enclave Status
```bash
# Real-time monitoring
watch -n 5 'sudo nitro-cli describe-enclaves | jq'
```

### Logs
```bash
# Enclave console (live logs)
sudo nitro-cli console --enclave-id <ENCLAVE_ID>
```

---

## 🔄 Updates and Maintenance

### Update Nautilus Code
```bash
# On EC2
cd truthMarket/nautilus-app
git pull

# Stop enclave
sudo nitro-cli terminate-enclave --enclave-id <ENCLAVE_ID>

# Rebuild
make -f Makefile.aws build

# Restart
make -f Makefile.aws run
./scripts/expose_enclave.sh

# Re-register (new key!)
./scripts/register_enclave.sh ...
```

### Backup Strategy
- **Code**: Git repository
- **PCRs**: Save `out/nitro.pcrs` after each build
- **Enclave ID**: Document in deployment notes
- **Public IP**: Use Elastic IP for stability

---

## ✅ Deployment Checklist

### Pre-Deployment
- [ ] AWS CLI configured
- [ ] SSH key pair exists in AWS
- [ ] Move contracts deployed
- [ ] EnclaveConfig created on-chain

### During Deployment
- [ ] EC2 instance launched
- [ ] Enclave built (.eif file created)
- [ ] Enclave running (describe-enclaves shows RUNNING)
- [ ] Health check passes locally
- [ ] Health check passes from internet
- [ ] Attestation endpoint works

### Post-Deployment
- [ ] Enclave registered on-chain
- [ ] Enclave object ID saved
- [ ] Frontend updated with new IDs
- [ ] End-to-end test passed
- [ ] Monitoring setup complete

---

## ❓ Frequently Asked Questions (FAQ)

### Q1: What CPU and memory configuration is recommended?

**Official Nautilus Recommendations:**
- **Instance Type**: m5.xlarge (4 vCPUs, 16GB RAM)
- **Enclave CPUs**: 2 cores (default in Makefile.aws line 53)
- **Enclave Memory**: 512MB (default in Makefile.aws line 54)
- **Allocator Reserve**: 3072MB (3GB) total allocated (setup-aws.sh line 184)

**Why these defaults?**
- TruthMarket Nautilus only verifies metadata (lightweight operation)
- 512MB is sufficient for metadata signing and attestation
- 2 CPUs handle concurrent requests well
- Leaves resources for parent EC2 instance operations

**Can I change them?**
✅ **YES** - Edit `Makefile.aws` line 53-54:
```makefile
# Default (recommended for TruthMarket):
--cpu-count 2 \
--memory 512M

# For heavier workloads (e.g., large datasets):
--cpu-count 4 \
--memory 1024M
```

**Important:** If you increase enclave resources, also update allocator:
```bash
# On EC2 instance
sudo nano /etc/nitro_enclaves/allocator.yaml

# Change:
memory_mib: 4096  # If using 1024M for enclave
cpu_count: 4      # If using 4 CPUs

# Restart allocator
sudo systemctl restart nitro-enclaves-allocator
```

**Cost Impact:**
| Configuration | Instance Type | Monthly Cost | Use Case |
|---------------|---------------|--------------|----------|
| **2 CPU, 512MB** (default) | m5.xlarge | **$140/mo** | ✅ TruthMarket (recommended) |
| 4 CPU, 1GB | m5.xlarge | **$140/mo** | Heavy metadata processing |
| 2 CPU, 512MB | m5.large | **$70/mo** | Budget option (slower) |
| 4 CPU, 2GB | m5.2xlarge | **$280/mo** | Multiple enclaves |

💡 **Recommendation for TruthMarket:** Stick with default 2 CPUs, 512MB - it's optimized for cost/performance.

---

### Q2: I don't have a domain. Can I still deploy?

**✅ YES! Domain is 100% OPTIONAL.**

**What the docs say:**
> "Optionally, you can set up an application load balancer (ALB) for the EC2 instance with an SSL/TLS certificate from AWS Certificate Manager (ACM), and configure Amazon Route 53 for DNS routing."

**Without a domain (using Public IP):**

**1. Access enclave via IP:**
```bash
# Your enclave URL
http://<PUBLIC_IP>:3000

# Example
http://3.88.45.123:3000/health
```

**2. Update frontend:**
```typescript
// truthmarket-frontend-v3/src/lib/constants.ts
export const CONFIG = {
  NAUTILUS_URL: "http://3.88.45.123:3000",  // Use public IP directly
  // ... rest of config
};
```

**3. Register enclave:**
```bash
# Use IP in registration
./scripts/register_enclave.sh \
  $ENCLAVE_PACKAGE_ID \
  $APP_PACKAGE_ID \
  $ENCLAVE_CONFIG_OBJECT_ID \
  http://3.88.45.123:3000 \  # Public IP, not domain!
  truthmarket \
  TRUTHMARKET
```

**⚠️ Limitations of using Public IP:**
- ❌ No HTTPS (traffic not encrypted between client and enclave)
- ❌ IP can change if instance restarts (use Elastic IP to fix this)
- ✅ Still works perfectly for hackathons/testing!
- ✅ Enclave attestation still cryptographically secure

---

### Q3: When do I NEED a domain?

**You ONLY need a domain if:**

1. **Production deployment** - For user-facing apps
2. **HTTPS required** - For encrypted client-to-enclave traffic
3. **Branding** - Want `https://verify.truthmarket.io` instead of IP
4. **Compliance** - Some use cases require SSL/TLS

**For TruthMarket hackathon:** ✅ Public IP is FINE!

**If you want a domain later:**

**Option A: Use Existing Domain**
1. Buy domain from Namecheap, GoDaddy, etc. (~$12/year)
2. Point A record to PUBLIC_IP
3. Set up Let's Encrypt SSL (free)

**Option B: AWS Full Setup ($$)**
1. Register domain in Route 53 (~$12/year)
2. Create Application Load Balancer (~$16/month)
3. Get SSL certificate from ACM (free)
4. Configure Route 53 DNS (~$0.50/month)

**Total cost with domain:** ~$170/month (instance) + $17/month (ALB + domain) = **$187/month**

💡 **Recommendation:** Start with Public IP, add domain if you go to production.

---

### Q4: How do I get a static IP (so it doesn't change)?

**Problem:** If EC2 instance restarts, PUBLIC_IP changes!

**Solution:** Use AWS Elastic IP (free while instance running)

```bash
# Allocate Elastic IP
aws ec2 allocate-address --region us-east-1

# Output:
# PublicIp: 3.88.45.123
# AllocationId: eipalloc-abc123

# Associate with instance
aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id eipalloc-abc123

# Now 3.88.45.123 is PERMANENT (even if instance restarts)
```

**Cost:**
- ✅ **FREE** while instance is running
- ⚠️ **$0.005/hour** ($3.60/month) if instance is stopped

---

### Q5: Can I use a smaller instance to save money?

**Yes, but with tradeoffs:**

| Instance Type | vCPUs | RAM | Cost/month | Enclave Support | Recommended? |
|---------------|-------|-----|------------|-----------------|--------------|
| m5.large | 2 | 8GB | **$70** | ✅ Yes | ⚠️ Budget option |
| **m5.xlarge** | 4 | 16GB | **$140** | ✅ Yes | ✅ **Recommended** |
| m5.2xlarge | 8 | 32GB | **$280** | ✅ Yes | ❌ Overkill |

**m5.large limitations:**
- Only 2 vCPUs total (enclave uses 2, parent gets 0)
- Only 8GB RAM (allocator gets 3GB, parent gets 5GB)
- Slower build times (10-15 min becomes 20-30 min)
- Can't run multiple enclaves

💡 **Recommendation:** Use m5.xlarge for smooth experience.

---

### Q6: What if I get "insufficient CPU" error?

**Error:**
```
Insufficient CPUs available in the pool
```

**Cause:** Allocator hasn't reserved CPUs for enclaves

**Fix:**
```bash
# Check allocator config
cat /etc/nitro_enclaves/allocator.yaml

# Should show:
cpu_count: 2
memory_mib: 3072

# Restart allocator
sudo systemctl restart nitro-enclaves-allocator
sudo systemctl status nitro-enclaves-allocator
```

---

### Q7: How much does this cost per month?

**TruthMarket Default Setup:**
```
EC2 Instance (m5.xlarge):  $140/month
EBS Storage (200GB):        $20/month
Data Transfer:              ~$5/month
Security Group:             FREE
--------------------------------------
Total:                      ~$165/month
```

**Cost Reduction Options:**
1. **Reserved Instance (1-year)**: Save 40% → **$100/month**
2. **Reserved Instance (3-year)**: Save 60% → **$68/month**
3. **Smaller instance (m5.large)**: **$70/month** (slower)
4. **Less storage (100GB)**: Save $10/month

⚠️ **DON'T use Spot Instances** - Enclave restart = new ephemeral key!

---

### Q8: Can I stop the instance when not using it?

**⚠️ WARNING: Not recommended for production!**

**What happens when you stop:**
- ✅ Save money (no instance charges)
- ❌ **Enclave key is LOST** (ephemeral!)
- ❌ Public IP changes (unless Elastic IP)
- ❌ Must re-register enclave on-chain

**If you must stop:**
```bash
# Stop instance
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# Later, restart
aws ec2 start-instances --instance-ids $INSTANCE_ID

# Must do again:
1. Build enclave (if code changed)
2. Run enclave (generates NEW key)
3. Expose enclave
4. Register enclave (new Enclave object!)
5. Update frontend (new ENCLAVE_OBJECT_ID)
```

💡 **Better option:** Keep running for hackathon, shut down when done.

---

### Q9: Can I access the enclave from my frontend localhost?

**During development:**

**Option A: Tunnel from Mac to AWS**
```bash
# On your Mac
ssh -L 3000:localhost:3000 ec2-user@<PUBLIC_IP>

# Now in frontend:
NAUTILUS_URL: "http://localhost:3000"  # Tunnels to AWS!
```

**Option B: Use public IP directly**
```typescript
// Frontend points to AWS
NAUTILUS_URL: "http://<PUBLIC_IP>:3000"
```

**⚠️ CORS Warning:** Enclave must allow your frontend origin!

---

### Q10: How do I monitor enclave health?

**Check if running:**
```bash
# On EC2 instance
sudo nitro-cli describe-enclaves | jq
```

**Health check:**
```bash
# Locally
curl http://localhost:3000/health

# From internet
curl http://<PUBLIC_IP>:3000/health
```

**Set up monitoring script:**
```bash
# Create monitor.sh
cat > monitor.sh <<'EOF'
#!/bin/bash
while true; do
  STATUS=$(curl -s http://localhost:3000/health)
  if [ "$STATUS" = "OK" ]; then
    echo "$(date): ✅ Enclave healthy"
  else
    echo "$(date): ❌ Enclave down!"
    # Optional: restart enclave
  fi
  sleep 60
done
EOF

chmod +x monitor.sh
nohup ./monitor.sh > monitor.log 2>&1 &
```

---

## 📚 Additional Resources

- [AWS Nitro Enclaves Documentation](https://docs.aws.amazon.com/enclaves/)
- [Nautilus Official Repo](https://github.com/MystenLabs/nautilus)
- [Sui Move Documentation](https://docs.sui.io/concepts/sui-move-concepts)
- [TruthMarket Architecture](../ARCHITECTURE.md)
- [AWS EC2 Pricing Calculator](https://calculator.aws/)
- [AWS Elastic IP Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html)

---

## 🆘 Support

**Issues?**
1. Check troubleshooting section above
2. Review AWS CloudWatch logs
3. Check Sui Explorer for on-chain status
4. Contact team on Discord

---

**Congratulations! Your TruthMarket Nautilus enclave is now running in production on AWS Nitro! 🎉**

*Last Updated: 2025-11-21*
