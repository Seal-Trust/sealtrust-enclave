# TruthMarket Nautilus - Deployment Information

**Deployment Date**: 2025-11-22
**Network**: Sui Testnet
**Status**: LIVE

---

## Deployed Contracts

### Enclave Package (Official Nautilus)
- **Package ID**: `0x0ff344b5b6f07b79b56a4ce1e9b1ef5a96ba219f6e6f2c49f194dee29dfc8b7f`
- **Module**: `enclave`

### TruthMarket Verification Package
- **Package ID**: `0xe9cc4d6d70a38c9e32c296007deb67d1503a2d77963f2b9e0782cc396a68834a`
- **Module**: `truthmarket`
- **OTW**: `TRUTHMARKET`
- **Publish Transaction**: `FmYHkxTHuVjJk7zjyCHpwKRELaz3FgD5fXME9z29RjVm`

---

## On-Chain Objects

### EnclaveConfig (Shared)
- **Object ID**: `0x97991f6c063f189b50b395ad21545fd17377f95e08586fa99a23b6fc131a4c07`
- **Type**: `EnclaveConfig<truthmarket::TRUTHMARKET>`
- **Name**: `truthmarket dataset enclave`
- **Sui Explorer**: https://testnet.suivision.xyz/object/0x97991f6c063f189b50b395ad21545fd17377f95e08586fa99a23b6fc131a4c07

### Enclave (Shared)
- **Object ID**: `0x2f48b9d38d71982ad858f679ce8c1f3975b1dfc76900a673f0046eb9d2021f3f`
- **Type**: `Enclave<truthmarket::TRUTHMARKET>`
- **Registration Transaction**: `4SAWoZy3a88f5V1a4zaTU1S2WxxNWbFTjmdk7JtLc8Dn`
- **Sui Explorer**: https://testnet.suivision.xyz/object/0x2f48b9d38d71982ad858f679ce8c1f3975b1dfc76900a673f0046eb9d2021f3f

### Cap (Owned by Admin)
- **Object ID**: `0xeb27265a2bf84335f3f76b3670b4fc826ece92e42111ee7d99660fc57c939cf4`
- **Owner**: `0x5d13269c32b064c8ac94bddb5b6cbe6beddba61d68cbea27e993476e73004fe5`

---

## AWS Infrastructure

### EC2 Instance
- **Instance ID**: `i-09a12ed402b0c7199`
- **Public IP**: `13.217.44.235`
- **Instance Type**: `m5a.xlarge`
- **Region**: `us-east-1`

### Enclave
- **Enclave ID**: `i-09a12ed402b0c7199-enc19aaa8be4a6acc7`
- **Enclave CID**: `21`
- **Memory**: `1024 MiB`
- **CPUs**: `2`

---

## PCR Measurements

```
PCR0: de2a359344076e2125fe2f2a779e028db93d17d9710230304e6b6a979386711c7f04f269ab37d78c7fbbeb40bb815a12
PCR1: de2a359344076e2125fe2f2a779e028db93d17d9710230304e6b6a979386711c7f04f269ab37d78c7fbbeb40bb815a12
PCR2: 21b9efbc184807662e966d34f390821309eeac6802309798826296bf3e8bec7c10edb30948c90ba67310f7b964fc500a
```

---

## API Endpoints

### Public URL
- **Base URL**: `http://13.217.44.235:3000`

### Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Simple health check |
| `/health_check` | GET | Full health check with endpoint status |
| `/get_attestation` | GET | Get NSM attestation document |
| `/verify_metadata` | POST | Verify and sign dataset metadata (V3) |
| `/process_data` | POST | Legacy endpoint (deprecated) |

### Test Commands
```bash
# Health check
curl http://13.217.44.235:3000/health

# Get attestation
curl http://13.217.44.235:3000/get_attestation

# Verify metadata
curl -X POST http://13.217.44.235:3000/verify_metadata \
  -H "Content-Type: application/json" \
  -d '{"metadata": {...}}'
```

---

## Transaction History

| Action | Transaction Digest | Date |
|--------|-------------------|------|
| Publish TruthMarket | `FmYHkxTHuVjJk7zjyCHpwKRELaz3FgD5fXME9z29RjVm` | 2025-11-22 |
| Update PCRs (v1) | `J3VtdJnFEbeTjDPiJDo8yGwn655hCp5xJXBRhNwjqo6A` | 2025-11-22 |
| Update PCRs (v2) | `4w7bzouUWrd6P8EZmScRNZoAdQ15zUrEfKkB81ku9yt5` | 2025-11-22 |
| Register Enclave | `4SAWoZy3a88f5V1a4zaTU1S2WxxNWbFTjmdk7JtLc8Dn` | 2025-11-22 |

---

## GitHub Repositories

| Repository | URL |
|------------|-----|
| Nautilus Enclave | https://github.com/TruthMarket/nautilus-enclave |
| Contracts | https://github.com/TruthMarket/contracts |
| Frontend | https://github.com/TruthMarket/frontend |
| Seal Key Server | https://github.com/TruthMarket/seal-key-server |

---

## Frontend Configuration

Update your frontend with these values:

```typescript
export const CONFIG = {
  // Sui Network
  NETWORK: 'testnet',

  // Contract Package IDs
  ENCLAVE_PACKAGE_ID: '0x0ff344b5b6f07b79b56a4ce1e9b1ef5a96ba219f6e6f2c49f194dee29dfc8b7f',
  APP_PACKAGE_ID: '0xe9cc4d6d70a38c9e32c296007deb67d1503a2d77963f2b9e0782cc396a68834a',

  // On-chain Objects
  ENCLAVE_CONFIG_ID: '0x97991f6c063f189b50b395ad21545fd17377f95e08586fa99a23b6fc131a4c07',
  ENCLAVE_OBJECT_ID: '0x2f48b9d38d71982ad858f679ce8c1f3975b1dfc76900a673f0046eb9d2021f3f',

  // Nautilus Enclave
  NAUTILUS_URL: 'http://13.217.44.235:3000',
};
```

---

## Maintenance Commands

### On EC2 Instance

```bash
# SSH into instance
ssh truthmarket-enclave

# Check enclave status
nitro-cli describe-enclaves

# Restart enclave
sudo nitro-cli terminate-enclave --all
make -f Makefile.aws run
./scripts/expose_enclave.sh

# View enclave console (debug mode only)
sudo nitro-cli console --enclave-id $(sudo nitro-cli describe-enclaves | jq -r '.[0].EnclaveID')

# Check socat proxy
ps aux | grep socat

# Restart proxy
pkill -f socat
socat TCP4-LISTEN:3000,reuseaddr,fork VSOCK-CONNECT:21:3000 &
```

### Update PCRs (after code changes)

```bash
# Build locally to get new PCRs
make -f Makefile.aws aws-build
cat out/nitro.pcrs

# Update on-chain
sui client call --function update_pcrs --module enclave \
  --package 0x0ff344b5b6f07b79b56a4ce1e9b1ef5a96ba219f6e6f2c49f194dee29dfc8b7f \
  --type-args "0xe9cc4d6d70a38c9e32c296007deb67d1503a2d77963f2b9e0782cc396a68834a::truthmarket::TRUTHMARKET" \
  --args 0x97991f6c063f189b50b395ad21545fd17377f95e08586fa99a23b6fc131a4c07 \
  0xeb27265a2bf84335f3f76b3670b4fc826ece92e42111ee7d99660fc57c939cf4 \
  0x<NEW_PCR0> 0x<NEW_PCR1> 0x<NEW_PCR2> \
  --gas-budget 10000000
```

---

## Security Notes

1. **PCRs are immutable measurements** - Any code change will produce different PCRs
2. **Ephemeral keys** - Enclave generates new keypair on each boot
3. **Attestation verification** - Use `load_nitro_attestation` on-chain to verify
4. **Admin Cap** - Required to update PCRs or destroy enclaves

---

*Last Updated: 2025-11-22*
