#!/bin/bash

# Ethereum Node Setup Script
# This script automates the setup of Geth (execution) and Prysm (consensus) clients
# Usage: ./eth_node_setup.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check command success
check_success() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: $1 failed${NC}"
        exit 1
    fi
}

# Step 1: System Update
echo -e "${YELLOW}[1/13] Updating system packages...${NC}"
sudo apt-get update && sudo apt-get upgrade -y
check_success "System update"

# Step 2: Install Dependencies
echo -e "${YELLOW}[2/13] Installing dependencies...${NC}"
sudo apt install curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev -y
check_success "Dependencies installation"

# Step 3: Docker Setup
echo -e "${YELLOW}[3/13] Setting up Docker...${NC}"

# Remove old Docker versions
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove $pkg -y
done

# Install Docker prerequisites
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg -y
check_success "Docker prerequisites"

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
check_success "Docker installation"

# Test Docker
sudo docker run hello-world
check_success "Docker test"

# Enable Docker service
sudo systemctl enable docker
sudo systemctl restart docker

# Step 4: Create Ethereum directories
echo -e "${YELLOW}[4/13] Creating Ethereum directories...${NC}"
mkdir -p /root/ethereum/execution
mkdir -p /root/ethereum/consensus
check_success "Directory creation"

# Step 5: Generate JWT secret
echo -e "${YELLOW}[5/13] Generating JWT secret...${NC}"
openssl rand -hex 32 > /root/ethereum/jwt.hex
check_success "JWT generation"

# Step 6: Create docker-compose.yml
echo -e "${YELLOW}[6/13] Creating docker-compose.yml...${NC}"
cat > /root/ethereum/docker-compose.yml << 'EOF'
services:
  geth:
    image: ethereum/client-go:stable
    container_name: geth
    restart: unless-stopped
    ports:
      - 30303:30303
      - 30303:30303/udp
      - 8545:8545
      - 8546:8546
      - 8551:8551
    volumes:
      - /root/ethereum/execution:/data
      - /root/ethereum/jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --http
      - --http.api=eth,net,web3
      - --http.addr=0.0.0.0
      - --authrpc.addr=0.0.0.0
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/data/jwt.hex
      - --authrpc.port=8551
      - --syncmode=snap
      - --datadir=/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  prysm:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain
    container_name: prysm
    restart: unless-stopped
    volumes:
      - /root/ethereum/consensus:/data
      - /root/ethereum/jwt.hex:/data/jwt.hex
    depends_on:
      - geth
    ports:
      - 4000:4000
      - 3500:3500
    command:
      - --sepolia
      - --accept-terms-of-use
      - --datadir=/data
      - --disable-monitoring
      - --rpc-host=0.0.0.0
      - --execution-endpoint=http://geth:8551
      - --jwt-secret=/data/jwt.hex
      - --rpc-port=4000
      - --grpc-gateway-corsdomain=*
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=3500
      - --min-sync-peers=7
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
check_success "docker-compose.yml creation"

# Step 7: Install net-tools
echo -e "${YELLOW}[7/13] Installing net-tools...${NC}"
sudo apt update
sudo apt install net-tools -y
check_success "net-tools installation"

# Step 8: Check ports
echo -e "${YELLOW}[8/13] Checking ports...${NC}"
sudo netstat -tuln | grep -E '30303|8545|8546|8551|4000|3500'

# Step 9: Start containers
echo -e "${YELLOW}[9/13] Starting containers...${NC}"
cd /root/ethereum
docker compose up -d
check_success "Container startup"

# Step 10: View logs
echo -e "${YELLOW}[10/13] Viewing initial logs...${NC}"
docker compose logs -fn 100

# Step 11: Configure firewall
echo -e "${YELLOW}[11/13] Configuring firewall...${NC}"
sudo ufw allow 22
sudo ufw allow ssh
sudo ufw enable
check_success "Firewall basic setup"

# Step 12: Allow Ethereum ports
echo -e "${YELLOW}[12/13] Allowing Ethereum ports...${NC}"
sudo ufw allow 8545/tcp    # Geth HTTP RPC
sudo ufw allow 3500/tcp    # Prysm HTTP API
sudo ufw allow 30303/tcp   # Geth P2P
sudo ufw allow 30303/udp   # Geth P2P
check_success "Firewall Ethereum ports"

# Step 13: Display monitoring commands
echo -e "${GREEN}[13/13] Setup complete!${NC}"
echo -e "\n${YELLOW}Monitoring Commands:${NC}"
echo -e "1. Check Geth sync status:"
echo "   curl -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://localhost:8545"
echo -e "\n2. Check Prysm sync status:"
echo "   curl http://localhost:3500/eth/v1/node/syncing"
echo -e "\n3. View container logs:"
echo "   cd /root/ethereum && docker compose logs -fn 100"
echo -e "\n4. Check running containers:"
echo "   docker ps"
echo -e "\n${GREEN}Your Ethereum node is now running!${NC}"