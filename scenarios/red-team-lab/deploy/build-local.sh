#!/bin/bash
# Build Red Team Lab images locally for direct use with CYROID
# No registry push required - CYROID uses local Docker daemon
# Skips building if images already exist (use --force to rebuild)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$SCRIPT_DIR/../containers"
FORCE_BUILD=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --force|-f) FORCE_BUILD=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Function to check if image exists and is up-to-date
image_exists() {
    local image_name="$1"
    if docker image inspect "$image_name" &>/dev/null; then
        return 0
    fi
    return 1
}

# Function to build image if needed
build_if_needed() {
    local step="$1"
    local total="$2"
    local image_name="$3"
    local build_dir="$4"
    local description="$5"

    echo ""
    echo "[$step/$total] $description"

    if [ "$FORCE_BUILD" = true ]; then
        echo "  -> Force rebuild requested"
        docker build -t "$image_name" "$build_dir"
    elif image_exists "$image_name"; then
        echo "  -> Image already exists, skipping (use --force to rebuild)"
    else
        echo "  -> Building..."
        docker build -t "$image_name" "$build_dir"
    fi
}

echo "=== Building Red Team Lab Images (Local) ==="
if [ "$FORCE_BUILD" = true ]; then
    echo "Force rebuild mode enabled"
fi

build_if_needed 1 4 "redteam-lab-kali:latest" "$CONTAINERS_DIR/kali/" \
    "Kali Attack Box (gobuster, sqlmap, impacket, metasploit, wordlists)"

build_if_needed 2 4 "redteam-lab-wordpress:latest" "$CONTAINERS_DIR/wordpress/" \
    "WordPress (SQLi target)"

build_if_needed 3 4 "redteam-lab-fileserver:latest" "$CONTAINERS_DIR/fileserver/" \
    "File Server"

build_if_needed 4 4 "redteam-lab-workstation:latest" "$CONTAINERS_DIR/workstation/" \
    "Workstation (BeEF victim)"

echo ""
echo "=== Build Complete ==="
echo ""
docker images | grep -E "redteam-lab" | head -10
echo ""
echo "Images are now available locally. CYROID can use them directly."
echo ""
echo "Next: Run the import script to create templates in CYROID:"
echo "  python deploy/import-to-cyroid.py --local"
