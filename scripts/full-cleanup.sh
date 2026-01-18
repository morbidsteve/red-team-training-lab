#!/bin/bash
# Full Cleanup Script - Removes ALL CYROID and Red Team Lab resources
set -e

CYROID_DIR="/Users/steven/programming/cyroid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "============================================"
echo "  Full Cleanup - CYROID + Red Team Lab"
echo "============================================"
echo ""

# Confirm
read -p "This will remove ALL CYROID containers, volumes, networks, and images. Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

log "Stopping CYROID..."
cd "$CYROID_DIR" 2>/dev/null && docker compose down -v --remove-orphans 2>/dev/null || true

log "Removing all CYROID range containers..."
docker ps -a --filter "name=cyroid-" -q | xargs -r docker rm -f 2>/dev/null || true

log "Removing CYROID networks..."
docker network ls --filter "name=cyroid" -q | xargs -r docker network rm 2>/dev/null || true
docker network rm traefik-routing 2>/dev/null || true

log "Removing CYROID volumes..."
docker volume ls --filter "name=cyroid" -q | xargs -r docker volume rm 2>/dev/null || true

log "Removing CYROID images..."
docker rmi cyroid-api cyroid-worker cyroid-frontend 2>/dev/null || true

log "Removing Red Team Lab images..."
docker images --filter "reference=redteam-lab-*" -q | xargs -r docker rmi -f 2>/dev/null || true

log "Removing dangling images..."
docker image prune -f 2>/dev/null || true

echo ""
log "Cleanup complete!"
echo ""

# Verify
echo "Remaining CYROID/RedTeam resources:"
docker ps -a | grep -E "cyroid|redteam" && echo "" || echo "  Containers: None"
docker images | grep -E "cyroid|redteam" && echo "" || echo "  Images: None"
docker network ls | grep -E "cyroid" && echo "" || echo "  Networks: None"
docker volume ls | grep -E "cyroid" && echo "" || echo "  Volumes: None"
