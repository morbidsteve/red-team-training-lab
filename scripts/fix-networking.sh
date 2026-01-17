#!/bin/bash
# Fix networking issues after deploying the Red Team Training Lab
# Run this after deploying the range in CYROID UI

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo "========================================"
echo "  Red Team Lab - Network Fix Script"
echo "========================================"
echo ""

# Find traefik container
TRAEFIK=$(docker ps --filter "name=traefik" --format "{{.Names}}" | head -1)
if [ -z "$TRAEFIK" ]; then
    error "Traefik container not found. Is CYROID running?"
fi
log "Found traefik: $TRAEFIK"

# Find all lab networks (cyroid-internet-*, cyroid-dmz-*, cyroid-internal-*)
LAB_NETWORKS=$(docker network ls --format "{{.Name}}" | grep -E "^cyroid-(internet|dmz|internal)-" || true)

if [ -z "$LAB_NETWORKS" ]; then
    warn "No lab networks found. Have you deployed the range yet?"
    exit 0
fi

# Connect traefik to each lab network
log "Connecting traefik to lab networks for console access..."
for net in $LAB_NETWORKS; do
    if docker network inspect "$net" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "$TRAEFIK"; then
        echo "  [SKIP] $net (already connected)"
    else
        docker network connect "$net" "$TRAEFIK" 2>/dev/null && echo "  [OK] $net" || echo "  [FAIL] $net"
    fi
done

# Find webserver and connect to internet network if not already
WEBSERVER=$(docker ps --filter "name=webserver" --format "{{.Names}}" | head -1)
if [ -n "$WEBSERVER" ]; then
    log "Checking webserver multi-homing..."
    INTERNET_NET=$(echo "$LAB_NETWORKS" | grep "internet" | head -1)
    if [ -n "$INTERNET_NET" ]; then
        if docker network inspect "$INTERNET_NET" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "$WEBSERVER"; then
            echo "  [SKIP] Webserver already on internet network"
        else
            # Get the expected IP (172.16.0.100 or similar based on subnet)
            SUBNET=$(docker network inspect "$INTERNET_NET" --format '{{(index .IPAM.Config 0).Subnet}}' | cut -d'/' -f1 | sed 's/\.0$//')
            TARGET_IP="${SUBNET}.100"
            docker network connect --ip "$TARGET_IP" "$INTERNET_NET" "$WEBSERVER" 2>/dev/null && \
                echo "  [OK] Connected webserver to $INTERNET_NET ($TARGET_IP)" || \
                echo "  [FAIL] Could not connect webserver"
            docker restart "$WEBSERVER" >/dev/null 2>&1
            log "Restarted webserver to apply network changes"
        fi
    fi
fi

echo ""
log "Network fix complete!"
echo ""
echo "You can now:"
echo "  - Access VM consoles from the CYROID UI"
echo "  - Run nmap scans from Kali to discover targets"
echo ""
