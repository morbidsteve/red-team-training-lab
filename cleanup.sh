#!/bin/bash
# Red Team Training Lab - Cleanup Script
# Removes all lab resources so you can start fresh with setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYROID_DIR="${CYROID_DIR:-$SCRIPT_DIR/../cyroid}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "   Red Team Training Lab - Cleanup"
echo "=============================================="
echo ""

# Check for --full flag
FULL_CLEANUP=false
FORCE=false
for arg in "$@"; do
    case $arg in
        --full)
            FULL_CLEANUP=true
            ;;
        --force|-f)
            FORCE=true
            ;;
    esac
done

if [ "$FORCE" != "true" ]; then
    warn "This will remove all Red Team Lab resources!"
    echo ""
    echo "  Options:"
    echo "    cleanup.sh          - Remove lab VMs and networks only"
    echo "    cleanup.sh --full   - Also remove CYROID platform and all data"
    echo "    cleanup.sh --force  - Skip confirmation prompts"
    echo ""
    read -p "Continue? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Step 1: Stop and remove lab VM containers
log "Stopping lab VM containers..."
LAB_CONTAINERS=$(docker ps -a --filter "name=cyroid-" --format "{{.Names}}" | grep -v -E "cyroid-(api|worker|db|minio|frontend|redis|traefik)-" || true)

if [ -n "$LAB_CONTAINERS" ]; then
    echo "$LAB_CONTAINERS" | while read container; do
        echo "  Removing: $container"
        docker rm -f "$container" 2>/dev/null || true
    done
    log "Lab containers removed"
else
    log "No lab containers found"
fi

# Step 2: Remove lab networks
log "Removing lab networks..."
LAB_NETWORKS=$(docker network ls --filter "name=cyroid-" --format "{{.Name}}" | grep -v "cyroid_default" || true)

if [ -n "$LAB_NETWORKS" ]; then
    echo "$LAB_NETWORKS" | while read network; do
        echo "  Removing: $network"
        docker network rm "$network" 2>/dev/null || true
    done
    log "Lab networks removed"
else
    log "No lab networks found"
fi

# Step 3: Full cleanup (optional)
if [ "$FULL_CLEANUP" = "true" ]; then
    echo ""
    warn "Performing FULL cleanup..."

    # Stop CYROID platform
    if [ -d "$CYROID_DIR" ]; then
        log "Stopping CYROID platform..."
        cd "$CYROID_DIR"
        docker compose down -v 2>/dev/null || true
        cd "$SCRIPT_DIR"
        log "CYROID platform stopped"
    fi

    # Remove CYROID data
    if [ -d "/data/cyroid" ]; then
        log "Removing CYROID data directory..."
        sudo rm -rf /data/cyroid
        log "CYROID data removed"
    fi

    # Remove CYROID repo
    if [ -d "$CYROID_DIR" ]; then
        log "Removing CYROID directory..."
        rm -rf "$CYROID_DIR"
        log "CYROID directory removed"
    fi

    # Remove any remaining cyroid containers
    log "Removing any remaining CYROID containers..."
    docker ps -a --filter "name=cyroid" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true

    # Remove cyroid_default network
    docker network rm cyroid_default 2>/dev/null || true
fi

echo ""
log "Cleanup complete!"
echo ""

if [ "$FULL_CLEANUP" = "true" ]; then
    echo "To start fresh, run:"
    echo "  ./setup.sh"
else
    echo "Lab VMs and networks removed."
    echo "CYROID platform is still running."
    echo ""
    echo "To redeploy the lab, use the CYROID web UI or run:"
    echo "  ./setup.sh"
    echo ""
    echo "For full cleanup (including CYROID), run:"
    echo "  ./cleanup.sh --full"
fi
