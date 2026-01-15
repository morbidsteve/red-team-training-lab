#!/bin/bash
# Red Team Training Lab - One-Click Setup
# Sets up CYROID + imports the attack training lab

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
prompt() { echo -e "${CYAN}[?]${NC} $1"; }

# Default credentials (can be overridden via env vars)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@redteamlab.local}"
ADMIN_PASS="${ADMIN_PASS:-RedTeam2024!}"

echo ""
echo "=============================================="
echo "   Red Team Training Lab - Setup Script"
echo "=============================================="
echo ""

# ----------------------------
# Step 0: Choose CYROID Instance
# ----------------------------
prompt "Where do you want to deploy the Red Team Lab?"
echo ""
echo "  1) Local - Set up CYROID on this machine (default)"
echo "  2) Remote - Use an existing CYROID instance"
echo ""
read -p "Enter choice [1]: " DEPLOY_CHOICE
DEPLOY_CHOICE="${DEPLOY_CHOICE:-1}"

if [ "$DEPLOY_CHOICE" == "2" ]; then
    # Remote deployment
    echo ""
    read -p "Enter CYROID API URL (e.g., https://cyroid.example.com/api): " REMOTE_API_URL
    if [ -z "$REMOTE_API_URL" ]; then
        error "API URL is required"
    fi

    read -p "Enter your username: " REMOTE_USER
    read -s -p "Enter your password: " REMOTE_PASS
    echo ""

    # Skip to remote deployment section
    DEPLOY_MODE="remote"
    API_URL="$REMOTE_API_URL"
    ADMIN_USER="$REMOTE_USER"
    ADMIN_PASS="$REMOTE_PASS"
else
    DEPLOY_MODE="local"
fi

echo ""

# ----------------------------
# Step 1: Check Prerequisites
# ----------------------------
log "Checking prerequisites..."

# Docker (always needed for building images)
if ! command -v docker &> /dev/null; then
    error "Docker not installed. Install with: sudo apt install docker.io docker-compose-v2"
fi

# Check if user can run docker
if ! docker ps &> /dev/null; then
    error "Cannot run docker. Add yourself to docker group: sudo usermod -aG docker \$USER (then logout/login)"
fi

# Python3
if ! command -v python3 &> /dev/null; then
    error "Python3 not installed. Install with: sudo apt install python3 python3-pip"
fi

# requests module
if ! python3 -c "import requests" &> /dev/null; then
    log "Installing Python requests module..."
    pip3 install requests --quiet
fi

if [ "$DEPLOY_MODE" == "local" ]; then
    # Docker Compose v2 (only for local)
    if ! docker compose version &> /dev/null; then
        error "Docker Compose v2 not found. Install with: sudo apt install docker-compose-v2"
    fi

    # KVM (optional but recommended for Windows VMs)
    if [ -e /dev/kvm ]; then
        log "KVM available - Windows VMs will use hardware acceleration"
    else
        warn "KVM not available - Windows VMs will be slow (software emulation)"
        warn "To enable: sudo apt install qemu-kvm && sudo usermod -aG kvm \$USER"
    fi
fi

log "Prerequisites OK"

# ----------------------------
# Local Setup (skip for remote)
# ----------------------------
if [ "$DEPLOY_MODE" == "local" ]; then

    # ----------------------------
    # Step 2: Create Data Directories
    # ----------------------------
    log "Creating data directories..."

    sudo mkdir -p /data/cyroid/{iso-cache,template-storage,vm-storage,shared}
    sudo chown -R $USER:$USER /data/cyroid

    # ----------------------------
    # Step 3: Setup Environment
    # ----------------------------
    log "Setting up environment..."

    if [ ! -f .env ]; then
        cp .env.example .env
        log "Created .env from template"
    else
        log ".env already exists, keeping existing config"
    fi

    # ----------------------------
    # Step 4: Start CYROID
    # ----------------------------
    log "Starting CYROID services..."

    docker compose up -d

    # Wait for services
    log "Waiting for services to start..."

    # Wait for API to be ready
    MAX_WAIT=120
    WAITED=0
    while ! curl -s http://localhost/api/health > /dev/null 2>&1; do
        if [ $WAITED -ge $MAX_WAIT ]; then
            # Try alternate endpoint
            if curl -s http://localhost:8000/health > /dev/null 2>&1; then
                break
            fi
            error "CYROID API didn't start within ${MAX_WAIT}s. Check logs: docker compose logs api"
        fi
        sleep 2
        WAITED=$((WAITED + 2))
        echo -ne "\r  Waiting for API... ${WAITED}s"
    done
    echo ""
    log "API is ready"

    # Determine API URL (traefik vs direct)
    if curl -s http://localhost/api/health > /dev/null 2>&1; then
        API_URL="http://localhost/api"
    else
        API_URL="http://localhost:8000"
    fi

    # ----------------------------
    # Step 5: Create Admin User
    # ----------------------------
    log "Creating admin user..."

    # Try to register (will fail if user exists, that's OK)
    REGISTER_RESP=$(curl -s -X POST "${API_URL}/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${ADMIN_USER}\",\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" 2>&1) || true

    if echo "$REGISTER_RESP" | grep -q "already"; then
        log "Admin user already exists"
    else
        log "Admin user created: ${ADMIN_USER}"
    fi

fi  # End local setup

# ----------------------------
# Step 6: Get Auth Token
# ----------------------------
log "Authenticating..."

LOGIN_RESP=$(curl -s -X POST "${API_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}")

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    error "Failed to get auth token. Response: $LOGIN_RESP"
fi

log "Authenticated successfully"

# ----------------------------
# Step 7: Build Lab Images
# ----------------------------
cd "$SCRIPT_DIR/scenarios/red-team-lab"

if [ "$DEPLOY_MODE" == "local" ]; then
    log "Building Red Team Lab container images..."
    ./deploy/build-local.sh
else
    warn "Remote mode: Images must be available on remote CYROID"
    echo ""
    echo "Options:"
    echo "  1) Use default images (ghcr.io/your-org/redteam-lab-*)"
    echo "  2) Build and push to a registry the remote CYROID can access"
    echo ""
    read -p "Press Enter to continue with default images, or Ctrl+C to cancel: "
fi

# ----------------------------
# Step 8: Import to CYROID
# ----------------------------
log "Importing Red Team Lab to CYROID..."

export CYROID_API_URL="$API_URL"
export CYROID_TOKEN="$TOKEN"

cd "$SCRIPT_DIR/scenarios/red-team-lab"
if [ "$DEPLOY_MODE" == "local" ]; then
    python3 deploy/import-to-cyroid.py --local
else
    python3 deploy/import-to-cyroid.py
fi

# ----------------------------
# Done!
# ----------------------------
echo ""
echo "=============================================="
echo -e "${GREEN}   Setup Complete!${NC}"
echo "=============================================="
echo ""

if [ "$DEPLOY_MODE" == "local" ]; then
    echo "CYROID UI:     http://localhost"
    echo "Admin User:    ${ADMIN_USER}"
    echo "Admin Pass:    ${ADMIN_PASS}"
    echo ""
    echo "Next Steps:"
    echo "  1. Open http://localhost in your browser"
    echo "  2. Login with credentials above"
    echo "  3. Go to Ranges -> Red Team Training Lab"
    echo "  4. Click 'Deploy' to start the environment"
    echo ""
    echo "To create more student environments:"
    echo "  export CYROID_TOKEN=${TOKEN}"
    echo "  python3 scenarios/red-team-lab/deploy/import-to-cyroid.py --local --range-name 'Student 2'"
else
    echo "Remote CYROID: ${API_URL}"
    echo ""
    echo "Next Steps:"
    echo "  1. Open your CYROID instance in a browser"
    echo "  2. Login with your credentials"
    echo "  3. Go to Ranges -> Red Team Training Lab"
    echo "  4. Click 'Deploy' to start the environment"
    echo ""
    echo "To create more student environments:"
    echo "  export CYROID_API_URL=${API_URL}"
    echo "  export CYROID_TOKEN=${TOKEN}"
    echo "  python3 scenarios/red-team-lab/deploy/import-to-cyroid.py --range-name 'Student 2'"
fi
echo ""
