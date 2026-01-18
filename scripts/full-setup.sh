#!/bin/bash
# Full Setup Script for CYROID + Red Team Training Lab
# Run this from scratch to get everything working
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
CYROID_DIR="/Users/steven/programming/cyroid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; }

# Parse arguments
SKIP_CLEANUP=false
SKIP_BUILD=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-cleanup) SKIP_CLEANUP=true ;;
        --skip-build) SKIP_BUILD=true ;;
        -h|--help)
            echo "Usage: $0 [--skip-cleanup] [--skip-build]"
            echo "  --skip-cleanup  Don't remove existing containers/images"
            echo "  --skip-build    Don't rebuild images (use existing)"
            exit 0
            ;;
        *) error "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

echo "============================================"
echo "  CYROID + Red Team Lab Full Setup"
echo "============================================"
echo ""

# Step 1: Cleanup
if [ "$SKIP_CLEANUP" = false ]; then
    log "Step 1: Cleaning up existing deployment..."

    # Stop CYROID
    if [ -d "$CYROID_DIR" ]; then
        cd "$CYROID_DIR"
        docker compose down -v --remove-orphans 2>/dev/null || true
    fi

    # Remove cyroid range containers
    docker ps -a --filter "name=cyroid-" -q | xargs -r docker rm -f 2>/dev/null || true

    # Remove cyroid networks
    docker network ls --filter "name=cyroid" -q | xargs -r docker network rm 2>/dev/null || true
    docker network rm traefik-routing 2>/dev/null || true

    # Remove images
    docker rmi cyroid-api cyroid-worker cyroid-frontend 2>/dev/null || true
    docker images --filter "reference=redteam-lab-*" -q | xargs -r docker rmi -f 2>/dev/null || true

    log "Cleanup complete"
else
    warn "Skipping cleanup"
fi

# Step 2: Setup CYROID
log "Step 2: Setting up CYROID..."
cd "$CYROID_DIR"

# Checkout latest version
git fetch --tags --force 2>/dev/null || true
LATEST_TAG=$(git describe --tags --abbrev=0 origin/master 2>/dev/null || echo "master")
log "Using CYROID version: $LATEST_TAG"
git checkout "$LATEST_TAG" 2>/dev/null || git checkout master

# Apply macOS path fix
if [[ "$(uname)" == "Darwin" ]]; then
    log "Applying macOS path fix..."
    MACOS_DATA_DIR="/Users/steven/Library/Application Support/cyroid"
    mkdir -p "$MACOS_DATA_DIR/iso-cache" "$MACOS_DATA_DIR/template-storage" "$MACOS_DATA_DIR/vm-storage" "$MACOS_DATA_DIR/shared"
    sed -i '' "s|/data/cyroid|$MACOS_DATA_DIR|g" docker-compose.yml
fi

# Start CYROID
log "Starting CYROID..."
docker compose up -d --build
log "Waiting for CYROID to be ready..."
sleep 15

# Check health
until curl -s http://localhost/api/v1/auth/login > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo ""
log "CYROID is ready"

# Create admin user if it doesn't exist
log "Ensuring admin user exists..."
USER_CHECK=$(curl -s -X POST http://localhost/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin@example.com","password":"admin"}' 2>/dev/null)

if echo "$USER_CHECK" | grep -q "Incorrect"; then
    log "Creating admin user..."
    curl -s -X POST http://localhost/api/v1/auth/register \
        -H "Content-Type: application/json" \
        -d '{"email":"admin@example.com","username":"admin@example.com","password":"admin","name":"Admin"}' > /dev/null
fi

# Fix VyOS template bug if present
docker compose exec -T db psql -U cyroid -d cyroid -c "UPDATE vm_templates SET default_disk_gb = 10 WHERE default_disk_gb < 10;" 2>/dev/null || true

# Step 3: Build Red Team Lab images
if [ "$SKIP_BUILD" = false ]; then
    log "Step 3: Building Red Team Lab images..."
    cd "$LAB_DIR/scenarios/red-team-lab/deploy"
    bash build-local.sh --force
else
    warn "Skipping image build"
fi

# Step 4: Import into CYROID
log "Step 4: Importing Red Team Lab into CYROID..."
cd "$LAB_DIR/scenarios/red-team-lab/deploy"

# Get auth token
CYROID_TOKEN=$(curl -s -X POST http://localhost/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin@example.com","password":"admin"}' | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))")

if [ -z "$CYROID_TOKEN" ] || [ "$CYROID_TOKEN" = "null" ]; then
    error "Failed to get CYROID auth token"
    exit 1
fi

export CYROID_TOKEN
python3 import-to-cyroid.py --local

echo ""
echo "============================================"
log "Setup Complete!"
echo "============================================"
echo ""
echo "CYROID URL:     http://localhost"
echo "Credentials:    admin@example.com / admin"
echo ""
echo "Next steps:"
echo "  1. Go to http://localhost"
echo "  2. Navigate to Ranges"
echo "  3. Click 'Red Team Training Lab'"
echo "  4. Click 'Deploy' to start the lab"
echo ""
