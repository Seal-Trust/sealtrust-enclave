#!/bin/bash
# Copyright (c), TruthMarket
# SPDX-License-Identifier: Apache-2.0
#
# TruthMarket Nautilus - AWS Nitro Enclave Setup
# This script launches an AWS EC2 instance with Nitro Enclaves enabled
# Based on official Nautilus configure_enclave.sh

set -e

############################
# Help Message
############################
show_help() {
    echo "==============================================="
    echo "  TruthMarket Nautilus - AWS Deployment"
    echo "==============================================="
    echo ""
    echo "This script launches an AWS EC2 instance (m5.xlarge) with Nitro Enclaves enabled"
    echo "for production deployment of TruthMarket metadata verification."
    echo ""
    echo "Prerequisites:"
    echo "  ✅ AWS CLI installed and configured"
    echo "  ✅ Environment variable KEY_PAIR set (your SSH key name)"
    echo "  ✅ allowed_endpoints.yaml configured"
    echo ""
    echo "Usage:"
    echo "  export KEY_PAIR=<your-key-pair-name>"
    echo "  export REGION=<aws-region>          # Optional, defaults to us-east-1"
    echo "  export AMI_ID=<ami-id>              # Optional, defaults to ami-085ad6ae776d8f09c"
    echo "  ./setup-aws.sh"
    echo ""
    echo "Example:"
    echo "  export KEY_PAIR=my-aws-key"
    echo "  ./setup-aws.sh"
    echo ""
    echo "What this script does:"
    echo "  1. Creates EC2 instance with Nitro Enclaves enabled"
    echo "  2. Configures security groups (ports 22, 443, 3000)"
    echo "  3. Installs Nitro CLI, Docker, and dependencies"
    echo "  4. Configures vsock-proxy for allowed endpoints"
    echo "  5. Provides instructions for building and running enclave"
    echo ""
    echo "After deployment:"
    echo "  - SSH to instance: ssh ec2-user@<PUBLIC_IP>"
    echo "  - Clone your repo with code"
    echo "  - Run: make -f Makefile.aws build"
    echo "  - Run: ./expose_enclave.sh"
    echo ""
    exit 0
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

############################
# Configurable Defaults
############################
REGION="${REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

# Default AMI for us-east-1 (Amazon Linux 2 with Nitro Enclaves support)
AMI_ID="${AMI_ID:-ami-085ad6ae776d8f09c}"

ALLOWLIST_PATH="../allowed_endpoints.yaml"

############################
# Cleanup Old Files
############################
echo "🧹 Cleaning up old configuration files..."
rm -f user-data.sh 2>/dev/null
rm -f trust-policy.json 2>/dev/null
rm -f secrets-policy.json 2>/dev/null

############################
# Validate Prerequisites
############################
if [ -z "$KEY_PAIR" ]; then
    echo "❌ Error: Environment variable KEY_PAIR is not set."
    echo "Please set it to your AWS SSH key pair name:"
    echo "  export KEY_PAIR=your-key-pair-name"
    exit 1
fi

# Check if yq is available
if ! command -v yq >/dev/null 2>&1; then
  echo "❌ Error: yq is not installed."
  echo "Please install yq:"
  echo "  macOS: brew install yq"
  echo "  Ubuntu: sudo apt-get install yq"
  exit 1
fi

############################
# Set the EC2 Instance Name
############################
if [ -z "$EC2_INSTANCE_NAME" ]; then
    read -p "Enter EC2 instance base name [truthmarket-nautilus]: " EC2_INSTANCE_NAME
    EC2_INSTANCE_NAME="${EC2_INSTANCE_NAME:-truthmarket-nautilus}"
fi

if command -v shuf >/dev/null 2>&1; then
    RANDOM_SUFFIX=$(shuf -i 100000-999999 -n 1)
else
    RANDOM_SUFFIX=$(printf "%06d" $(( RANDOM % 900000 + 100000 )))
fi

FINAL_INSTANCE_NAME="${EC2_INSTANCE_NAME}-${RANDOM_SUFFIX}"
echo "Instance will be named: $FINAL_INSTANCE_NAME"

#########################################
# Read endpoints from allowed_endpoints.yaml
#########################################
echo "📋 Reading allowed endpoints from $ALLOWLIST_PATH..."

if [ -f "$ALLOWLIST_PATH" ]; then
    ENDPOINTS=$(yq e '.endpoints | join(" ")' $ALLOWLIST_PATH 2>/dev/null)
    if [ -n "$ENDPOINTS" ]; then
        echo "Found endpoints:"
        echo "$ENDPOINTS"

        # Replace region placeholders
        ENDPOINTS=$(echo "$ENDPOINTS" \
          | sed "s|kms\.[^.]*\.amazonaws\.com|kms.$REGION.amazonaws.com|g" \
          | sed "s|secretsmanager\.[^.]*\.amazonaws\.com|secretsmanager.$REGION.amazonaws.com|g")

        echo "Endpoints after region patching:"
        echo "$ENDPOINTS"
    else
        echo "⚠️  No endpoints found in $ALLOWLIST_PATH. Continuing without additional endpoints."
    fi
else
    echo "⚠️  $ALLOWLIST_PATH not found. Continuing without additional endpoints."
    ENDPOINTS=""
fi

#########################################
# TruthMarket doesn't use AWS secrets
#########################################
echo "ℹ️  TruthMarket Nautilus doesn't require AWS Secrets Manager"
echo "   (No external API keys needed for metadata verification)"

USE_SECRET="n"
IAM_INSTANCE_PROFILE_OPTION=""
ROLE_NAME=""

#############################################################
# Create the user-data script (runs on instance boot)
#############################################################
echo "📝 Creating user-data script..."

cat <<'EOF' > user-data.sh
#!/bin/bash
# Update the instance and install Nitro Enclaves tools, Docker and other utilities
sudo yum update -y
sudo yum install -y aws-nitro-enclaves-cli-devel aws-nitro-enclaves-cli docker nano socat git make jq

# Add the current user to the docker group
sudo usermod -aG docker ec2-user

# Start and enable Nitro Enclaves allocator and Docker services
sudo systemctl start nitro-enclaves-allocator.service && sudo systemctl enable nitro-enclaves-allocator.service
sudo systemctl start docker && sudo systemctl enable docker
sudo systemctl enable nitro-enclaves-vsock-proxy.service
EOF

# Append endpoint configuration to vsock-proxy YAML
if [ -n "$ENDPOINTS" ]; then
    for ep in $ENDPOINTS; do
        echo "echo \"- {address: $ep, port: 443}\" | sudo tee -a /etc/nitro_enclaves/vsock-proxy.yaml" >> user-data.sh
    done
fi

# Continue the user-data script
cat <<'EOF' >> user-data.sh
# Stop the allocator so we can modify its configuration
sudo systemctl stop nitro-enclaves-allocator.service

# Adjust the enclave allocator memory (default set to 3072 MiB)
ALLOCATOR_YAML=/etc/nitro_enclaves/allocator.yaml
MEM_KEY=memory_mib
DEFAULT_MEM=3072
sudo sed -r "s/^(\s*${MEM_KEY}\s*:\s*).*/\1${DEFAULT_MEM}/" -i "${ALLOCATOR_YAML}"

# Restart the allocator with the updated memory configuration
sudo systemctl start nitro-enclaves-allocator.service && sudo systemctl enable nitro-enclaves-allocator.service
EOF

# Append vsock-proxy commands for each endpoint
if [ -n "$ENDPOINTS" ]; then
    PORT=8101
    for ep in $ENDPOINTS; do
        echo "vsock-proxy $PORT $ep 443 --config /etc/nitro_enclaves/vsock-proxy.yaml &" >> user-data.sh
        PORT=$((PORT+1))
    done
fi

###################################################################
# Update scripts/run.sh with endpoint configuration
###################################################################
if [ -n "$ENDPOINTS" ]; then
    echo "🔧 Configuring scripts/run.sh with endpoints..."

    ip=64
    endpoints_config=""
    for ep in $ENDPOINTS; do
        endpoints_config="${endpoints_config}echo \"127.0.0.${ip}   ${ep}\" >> /etc/hosts"$'\n'
        ip=$((ip+1))
    done

    # Remove existing endpoint lines
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' '/echo "127.0.0.[0-9]*   .*" >> \/etc\/hosts/d' scripts/run.sh
    else
        sed -i '/echo "127.0.0.[0-9]*   .*" >> \/etc\/hosts/d' scripts/run.sh
    fi

    # Add new endpoint configuration
    tmp_hosts="/tmp/endpoints_config.txt"
    echo "$endpoints_config" > "$tmp_hosts"

    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "/# ENDPOINT CONFIGURATION BLOCK/,/cat \/etc\/hosts/ {
            /# ENDPOINT CONFIGURATION BLOCK/a\\
$endpoints_config
        }" scripts/run.sh
    else
        sed -i "/# ENDPOINT CONFIGURATION BLOCK/a\\
$endpoints_config" scripts/run.sh
    fi
    rm -f "$tmp_hosts"
fi

############################
# Create or Use Security Group
############################
echo "🔒 Setting up security group..."
SECURITY_GROUP_NAME="truthmarket-nautilus-sg"

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --group-names "$SECURITY_GROUP_NAME" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null)

if [ "$SECURITY_GROUP_ID" = "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
  echo "Creating security group $SECURITY_GROUP_NAME..."
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Security group for TruthMarket Nautilus: SSH (22), HTTPS (443), Nautilus (3000)" \
    --query "GroupId" --output text)

  if [ $? -ne 0 ]; then
    echo "❌ Error creating security group."
    exit 1
  fi

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 3000 --cidr 0.0.0.0/0
else
  echo "Using existing security group $SECURITY_GROUP_NAME ($SECURITY_GROUP_ID)"
fi

############################
# Launch EC2 Instance
############################
echo "🚀 Launching EC2 instance with Nitro Enclaves enabled..."

INSTANCE_ID=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type m5.xlarge \
  --key-name "$KEY_PAIR" \
  --user-data file://user-data.sh \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":200}}]' \
  --enclave-options Enabled=true \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${FINAL_INSTANCE_NAME}},{Key=Project,Value=TruthMarket},{Key=Component,Value=Nautilus}]" \
  --query "Instances[0].InstanceId" --output text)

echo "Instance launched with ID: $INSTANCE_ID"

echo "⏳ Waiting for instance $INSTANCE_ID to run..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

sleep 10

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text)

############################
# Success Message
############################
echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ AWS EC2 Instance Configured Successfully!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Instance Details:"
echo "  Name:       $FINAL_INSTANCE_NAME"
echo "  ID:         $INSTANCE_ID"
echo "  Public IP:  $PUBLIC_IP"
echo "  Region:     $REGION"
echo "  Type:       m5.xlarge (Nitro Enclaves enabled)"
echo ""
echo "Next Steps:"
echo ""
echo "1. Wait 2-3 minutes for instance initialization to complete"
echo ""
echo "2. SSH into the instance:"
echo "   ssh ec2-user@$PUBLIC_IP"
echo ""
echo "3. Clone your TruthMarket repository:"
echo "   git clone <your-repo-url>"
echo "   cd truthMarket/nautilus-app"
echo ""
echo "4. Build the enclave .eif file:"
echo "   make -f Makefile.aws build"
echo ""
echo "5. Run the enclave:"
echo "   make -f Makefile.aws run"
echo ""
echo "6. Expose the enclave to the internet:"
echo "   ./expose_enclave.sh"
echo ""
echo "7. Register the enclave on-chain:"
echo "   ./register_enclave.sh <ENCLAVE_PACKAGE_ID> <APP_PACKAGE_ID> <ENCLAVE_CONFIG_ID> http://$PUBLIC_IP:3000 <MODULE_NAME> <OTW_NAME>"
echo ""
echo "Documentation: See AWS_DEPLOYMENT.md for detailed instructions"
echo "═══════════════════════════════════════════════════════"
