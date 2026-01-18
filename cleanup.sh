#!/bin/bash
# Red Team Training Lab - Cleanup Script
# Removes all lab resources so you can start fresh with setup.sh
#
# This script tries the smart approach first (CYROID API) and falls back
# to direct Docker cleanup if needed.

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
info() { echo -e "${CYAN}[*]${NC} $1"; }

echo ""
echo "=============================================="
echo "   Red Team Training Lab - Cleanup"
echo "=============================================="
echo ""

# Parse arguments
FULL_CLEANUP=false
FORCE=false
SKIP_API=false
for arg in "$@"; do
    case $arg in
        --full)
            FULL_CLEANUP=true
            ;;
        --force|-f)
            FORCE=true
            ;;
        --skip-api)
            SKIP_API=true
            ;;
        --help|-h)
            echo "Usage: cleanup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force, -f    Skip confirmation prompts"
            echo "  --full         Also remove CYROID platform and all data"
            echo "  --skip-api     Skip CYROID API cleanup (direct Docker only)"
            echo "  --help, -h     Show this help message"
            echo ""
            exit 0
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

# =============================================================================
# Step 1: Try CYROID API cleanup (preferred method)
# =============================================================================
API_CLEANUP_SUCCESS=false

if [ "$SKIP_API" != "true" ]; then
    log "Attempting cleanup via CYROID API..."

    # Try to get auth token (assuming default admin credentials or token file)
    CYROID_URL="${CYROID_URL:-http://localhost:80}"
    TOKEN_FILE="$HOME/.cyroid_token"

    if [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE")
    else
        # Try to login with default admin credentials
        info "Attempting to authenticate with CYROID..."
        TOKEN=$(curl -s -X POST "$CYROID_URL/api/v1/auth/login" \
            -H "Content-Type: application/json" \
            -d '{"email":"admin@cyroid.local","password":"admin123"}' \
            2>/dev/null | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    fi

    if [ -n "$TOKEN" ]; then
        info "Calling CYROID admin cleanup API..."
        CLEANUP_RESPONSE=$(curl -s -X POST "$CYROID_URL/api/v1/admin/cleanup-all" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"clean_database": true, "force": true}' \
            2>/dev/null)

        if echo "$CLEANUP_RESPONSE" | grep -q '"ranges_cleaned"'; then
            API_CLEANUP_SUCCESS=true
            RANGES=$(echo "$CLEANUP_RESPONSE" | grep -o '"ranges_cleaned":[0-9]*' | cut -d':' -f2)
            CONTAINERS=$(echo "$CLEANUP_RESPONSE" | grep -o '"containers_removed":[0-9]*' | cut -d':' -f2)
            NETWORKS=$(echo "$CLEANUP_RESPONSE" | grep -o '"networks_removed":[0-9]*' | cut -d':' -f2)
            log "CYROID API cleanup successful!"
            log "  Ranges cleaned: $RANGES"
            log "  Containers removed: $CONTAINERS"
            log "  Networks removed: $NETWORKS"
        else
            warn "CYROID API cleanup failed or returned unexpected response"
            warn "Response: $CLEANUP_RESPONSE"
        fi
    else
        warn "Could not authenticate with CYROID API"
    fi
fi

# =============================================================================
# Step 2: Docker-level cleanup (fallback or additional cleanup)
# =============================================================================
if [ "$API_CLEANUP_SUCCESS" != "true" ]; then
    warn "Falling back to direct Docker cleanup..."
fi

log "Performing Docker-level cleanup..."

# Stop and remove lab VM containers (not CYROID infrastructure)
info "Removing lab VM containers..."
LAB_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep "^cyroid-" | grep -v -E "^cyroid-(api|worker|db|minio|frontend|redis|traefik)-" || true)

if [ -n "$LAB_CONTAINERS" ]; then
    echo "$LAB_CONTAINERS" | while read container; do
        if [ -n "$container" ]; then
            echo "  Removing: $container"
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    log "Lab containers removed"
else
    info "No lab containers found"
fi

# Remove lab networks (disconnect traefik first to avoid "active endpoints" error)
info "Removing lab networks..."
LAB_NETWORKS=$(docker network ls --format "{{.Name}}" | grep "^cyroid-" | grep -v -E "^(cyroid-management|cyroid_default)$" || true)

if [ -n "$LAB_NETWORKS" ]; then
    # Find traefik container
    TRAEFIK_CONTAINER=$(docker ps --format "{{.Names}}" | grep "traefik" | head -1)

    echo "$LAB_NETWORKS" | while read network; do
        if [ -n "$network" ]; then
            # Disconnect traefik first if it exists
            if [ -n "$TRAEFIK_CONTAINER" ]; then
                docker network disconnect "$network" "$TRAEFIK_CONTAINER" 2>/dev/null || true
            fi
            echo "  Removing: $network"
            docker network rm "$network" 2>/dev/null || true
        fi
    done
    log "Lab networks removed"
else
    info "No lab networks found"
fi

# =============================================================================
# Step 3: Full cleanup (optional - removes CYROID platform itself)
# =============================================================================
if [ "$FULL_CLEANUP" = "true" ]; then
    echo ""
    warn "Performing FULL cleanup (including CYROID platform)..."

    # Stop CYROID platform
    if [ -d "$CYROID_DIR" ]; then
        log "Stopping CYROID platform..."
        cd "$CYROID_DIR"
        docker compose down -v 2>/dev/null || docker-compose down -v 2>/dev/null || true
        cd "$SCRIPT_DIR"
        log "CYROID platform stopped"
    fi

    # Remove CYROID data (check both Linux and macOS paths)
    MACOS_DATA_DIR="$HOME/Library/Application Support/cyroid"
    LINUX_DATA_DIR="/data/cyroid"

    if [ -d "$MACOS_DATA_DIR" ]; then
        log "Removing CYROID data directory (macOS)..."
        rm -rf "$MACOS_DATA_DIR"
        log "CYROID data removed"
    fi

    if [ -d "$LINUX_DATA_DIR" ]; then
        log "Removing CYROID data directory (Linux)..."
        sudo rm -rf "$LINUX_DATA_DIR" 2>/dev/null || rm -rf "$LINUX_DATA_DIR"
        log "CYROID data removed"
    fi

    # Remove any remaining cyroid containers
    log "Removing any remaining CYROID containers..."
    docker ps -a --format "{{.Names}}" | grep "^cyroid" | xargs -r docker rm -f 2>/dev/null || true

    # Remove cyroid networks
    log "Removing CYROID networks..."
    docker network ls --format "{{.Name}}" | grep "^cyroid" | xargs -r docker network rm 2>/dev/null || true

    # Remove cyroid volumes
    log "Removing CYROID volumes..."
    docker volume ls --format "{{.Name}}" | grep "^cyroid" | xargs -r docker volume rm 2>/dev/null || true

    # Remove Red Team Lab images (optional)
    info "Removing Red Team Lab images..."
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^(redteam-lab-|red-team-)" | xargs -r docker rmi -f 2>/dev/null || true
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
log "Cleanup complete!"
echo ""

# Show remaining resources
echo "Remaining CYROID resources:"
REMAINING_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep "^cyroid" | wc -l | tr -d ' ')
REMAINING_NETWORKS=$(docker network ls --format "{{.Name}}" | grep "^cyroid" | wc -l | tr -d ' ')
echo "  Containers: $REMAINING_CONTAINERS"
echo "  Networks: $REMAINING_NETWORKS"

echo ""
if [ "$FULL_CLEANUP" = "true" ]; then
    echo "To start fresh, run:"
    echo "  ./setup.sh"
else
    echo "Lab VMs and networks removed."
    if [ "$REMAINING_CONTAINERS" -gt 0 ]; then
        echo "CYROID platform is still running."
    fi
    echo ""
    echo "To redeploy the lab, use the CYROID web UI or run:"
    echo "  ./setup.sh"
    echo ""
    echo "For full cleanup (including CYROID), run:"
    echo "  ./cleanup.sh --full"
fi
