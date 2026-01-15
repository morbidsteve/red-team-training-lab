#!/bin/bash
# Build Red Team Lab images locally for direct use with CYROID
# No registry push required - CYROID uses local Docker daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$SCRIPT_DIR/../containers"

echo "=== Building Red Team Lab Images (Local) ==="
echo ""

# Build with simple local tags
echo "[1/3] Building WordPress (SQLi target)..."
docker build -t redteam-lab-wordpress:latest "$CONTAINERS_DIR/wordpress/"

echo ""
echo "[2/3] Building File Server..."
docker build -t redteam-lab-fileserver:latest "$CONTAINERS_DIR/fileserver/"

echo ""
echo "[3/3] Building Workstation (BeEF victim)..."
docker build -t redteam-lab-workstation:latest "$CONTAINERS_DIR/workstation/"

echo ""
echo "=== Build Complete ==="
echo ""
docker images | grep redteam-lab
echo ""
echo "Images are now available locally. CYROID can use them directly."
echo ""
echo "Next: Run the import script to create templates in CYROID:"
echo "  python deploy/import-to-cyroid.py --local"
