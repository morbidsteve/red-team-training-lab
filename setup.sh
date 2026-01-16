#!/bin/bash
# Red Team Training Lab - One-Click Setup
# Clones and sets up CYROID separately, then imports lab scenarios

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

# CYROID repo and version
CYROID_REPO="https://github.com/JongoDB/CYROID.git"
CYROID_DIR="${CYROID_DIR:-$SCRIPT_DIR/../cyroid}"

# Function to get latest release tag from GitHub
get_latest_cyroid_version() {
    local latest=""

    # Try GitHub tags API first
    local api_response=$(curl -sf "https://api.github.com/repos/JongoDB/CYROID/tags" 2>/dev/null)
    if [ -n "$api_response" ]; then
        latest=$(echo "$api_response" | python3 -c "import sys,json; tags=json.load(sys.stdin); print(tags[0]['name'] if tags else '')" 2>/dev/null)
    fi

    if [ -n "$latest" ]; then
        echo "$latest"
        return
    fi

    # Fallback: use git ls-remote to get latest tag (sorted by version)
    latest=$(git ls-remote --tags --sort=-v:refname "$CYROID_REPO" 2>/dev/null | \
        head -n1 | sed 's/.*refs\/tags\///' | sed 's/\^{}//')

    if [ -n "$latest" ]; then
        echo "$latest"
        return
    fi

    # Final fallback
    echo "main"
}

# Allow override via environment variable, otherwise fetch latest
CYROID_VERSION="${CYROID_VERSION:-$(get_latest_cyroid_version)}"

# Default credentials (can be overridden via env vars)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASS="${ADMIN_PASS:-RedTeam2024}"

# Domain Controller type: "samba" or "windows"
# Auto-detected based on OS and KVM availability
# Override with USE_SAMBA_DC=true to force Samba DC on Linux with KVM
DC_TYPE=""

echo ""
echo "=============================================="
echo "   Red Team Training Lab - Setup Script"
echo "=============================================="
echo ""

# ----------------------------
# Step 0: Choose CYROID Instance
# ----------------------------
# Can be set via environment: DEPLOY_CHOICE=1 (local) or DEPLOY_CHOICE=2 (remote)
if [ -z "$DEPLOY_CHOICE" ]; then
    prompt "Where do you want to deploy the Red Team Lab?"
    echo ""
    echo "  1) Local - Set up CYROID on this machine (default)"
    echo "  2) Remote - Use an existing CYROID instance"
    echo ""
    read -p "Enter choice [1]: " DEPLOY_CHOICE
fi
DEPLOY_CHOICE="${DEPLOY_CHOICE:-1}"

if [ "$DEPLOY_CHOICE" == "2" ]; then
    # Remote deployment
    echo ""
    read -p "Enter CYROID API URL (e.g., https://cyroid.example.com/api/v1): " REMOTE_API_URL
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

    # For remote mode, detect DC type based on local OS (assumes remote CYROID matches)
    OS_TYPE="$(uname -s)"
    if [ "$OS_TYPE" == "Darwin" ] || [ "${USE_SAMBA_DC:-false}" == "true" ]; then
        DC_TYPE="samba"
    else
        DC_TYPE="windows"
    fi
    export DC_TYPE
else
    DEPLOY_MODE="local"
fi

echo ""

# Ask how many student ranges to create
# Can be set via environment: NUM_STUDENTS=5
if [ -z "$NUM_STUDENTS" ]; then
    prompt "How many student lab environments do you want to create?"
    echo "  (Each student gets their own isolated network environment)"
    echo ""
    read -p "Enter number of students [1]: " NUM_STUDENTS
fi
NUM_STUDENTS="${NUM_STUDENTS:-1}"

# Validate it's a number
if ! [[ "$NUM_STUDENTS" =~ ^[0-9]+$ ]] || [ "$NUM_STUDENTS" -lt 1 ]; then
    error "Invalid number of students. Must be 1 or more."
fi

echo ""

# ----------------------------
# Step 1: Check Prerequisites
# ----------------------------
log "Checking prerequisites..."

# Detect OS for platform-specific instructions
HOST_OS="$(uname -s)"

# Docker (always needed for building images)
if ! command -v docker &> /dev/null; then
    if [ "$HOST_OS" == "Darwin" ]; then
        error "Docker not installed. Install Docker Desktop from https://docker.com/products/docker-desktop"
    else
        error "Docker not installed. Install with: sudo apt install docker.io docker-compose-v2"
    fi
fi

# Check if user can run docker
if ! docker ps &> /dev/null; then
    if [ "$HOST_OS" == "Darwin" ]; then
        error "Cannot connect to Docker. Make sure Docker Desktop is running."
    else
        error "Cannot run docker. Add yourself to docker group: sudo usermod -aG docker \$USER (then logout/login)"
    fi
fi

# Python3
if ! command -v python3 &> /dev/null; then
    if [ "$HOST_OS" == "Darwin" ]; then
        error "Python3 not installed. Install with: brew install python3"
    else
        error "Python3 not installed. Install with: sudo apt install python3 python3-pip"
    fi
fi

# requests module
if ! python3 -c "import requests" &> /dev/null; then
    log "Installing Python requests module..."
    if [ "$HOST_OS" == "Darwin" ]; then
        # macOS: use --user flag or pipx to avoid externally-managed-environment error
        pip3 install --user requests --quiet 2>/dev/null || pip3 install --break-system-packages requests --quiet
    else
        pip3 install requests --quiet
    fi
fi

# Git (needed to clone CYROID)
if ! command -v git &> /dev/null; then
    if [ "$HOST_OS" == "Darwin" ]; then
        error "Git not installed. Install with: brew install git"
    else
        error "Git not installed. Install with: sudo apt install git"
    fi
fi

if [ "$DEPLOY_MODE" == "local" ]; then
    # Docker Compose v2 (only for local)
    if ! docker compose version &> /dev/null; then
        if [ "$HOST_OS" == "Darwin" ]; then
            error "Docker Compose v2 not found. Update Docker Desktop to latest version."
        else
            error "Docker Compose v2 not found. Install with: sudo apt install docker-compose-v2"
        fi
    fi

    # Detect OS and KVM availability to determine DC type
    OS_TYPE="$(uname -s)"

    if [ "$OS_TYPE" == "Darwin" ]; then
        # macOS - always use Samba DC (no KVM support)
        DC_TYPE="samba"
        log "Detected macOS - using Samba AD DC (Windows DC requires KVM)"
    elif [ "$OS_TYPE" == "Linux" ]; then
        if [ -e /dev/kvm ]; then
            # Linux with KVM available
            if [ "${USE_SAMBA_DC:-false}" == "true" ]; then
                DC_TYPE="samba"
                log "USE_SAMBA_DC=true - using Samba AD DC"
            else
                DC_TYPE="windows"
                log "KVM available - using Windows DC (set USE_SAMBA_DC=true for faster Samba alternative)"
            fi
        else
            # Linux without KVM
            DC_TYPE="samba"
            warn "KVM not available - using Samba AD DC (Windows DC requires KVM for acceptable performance)"
            warn "To enable KVM on Linux: sudo apt install qemu-kvm && sudo usermod -aG kvm \$USER"
        fi
    else
        # Unknown OS - default to Samba
        DC_TYPE="samba"
        warn "Unknown OS ($OS_TYPE) - using Samba AD DC"
    fi

    export DC_TYPE
    log "Domain Controller type: $DC_TYPE"
fi

log "Prerequisites OK"

# ----------------------------
# Local Setup (skip for remote)
# ----------------------------
if [ "$DEPLOY_MODE" == "local" ]; then

    # ----------------------------
    # Step 2: Clone/Update CYROID
    # ----------------------------
    log "Setting up CYROID platform..."
    log "Using CYROID version: $CYROID_VERSION"

    if [ -d "$CYROID_DIR" ]; then
        log "CYROID directory exists at $CYROID_DIR"
        cd "$CYROID_DIR"

        # Check if it's a git repo
        if [ -d ".git" ]; then
            log "Updating CYROID..."
            git fetch origin --tags 2>/dev/null || true
        fi
    else
        log "Cloning CYROID from $CYROID_REPO..."
        git clone "$CYROID_REPO" "$CYROID_DIR"
        cd "$CYROID_DIR"
    fi

    # Checkout specific version
    log "Checking out CYROID $CYROID_VERSION..."
    git checkout "$CYROID_VERSION" 2>/dev/null || {
        warn "Version $CYROID_VERSION not found, using latest"
    }

    # ----------------------------
    # Step 3: Apply VNC routing fix (until PR is merged)
    # ----------------------------
    log "Applying VNC routing fix..."

    # Check if fix is already applied
    if ! grep -q "traefik.enable" backend/cyroid/api/ranges.py 2>/dev/null; then
        # Apply the fix using patch or sed
        cat > /tmp/vnc-fix.patch << 'PATCHEOF'
--- a/backend/cyroid/api/ranges.py
+++ b/backend/cyroid/api/ranges.py
@@ -182,11 +182,58 @@ def deploy_range(range_id: UUID, db: DBSession, current_user: CurrentUser):
                 if not network or not network.docker_network_id:
                     logger.warning(f"Skipping VM {vm.id}: network not provisioned")
                     continue

+                vm_id_short = str(vm.id)[:8]
                 labels = {
                     "cyroid.range_id": str(range_id),
                     "cyroid.vm_id": str(vm.id),
                     "cyroid.hostname": vm.hostname,
                 }

+                # Add traefik labels for VNC web console routing
+                display_type = vm.display_type or "desktop"
+                if display_type == "desktop":
+                    base_image = template.base_image or ""
+                    is_linuxserver = "linuxserver/" in base_image or "lscr.io/linuxserver" in base_image
+                    is_kasmweb = "kasmweb/" in base_image
+
+                    if base_image.startswith("iso:") or template.os_type == "windows":
+                        vnc_port = "8006"
+                        vnc_scheme = "http"
+                        needs_auth = False
+                    elif is_linuxserver:
+                        vnc_port = "3000"
+                        vnc_scheme = "http"
+                        needs_auth = False
+                    elif is_kasmweb:
+                        vnc_port = "6901"
+                        vnc_scheme = "https"
+                        needs_auth = True
+                    else:
+                        vnc_port = "6901"
+                        vnc_scheme = "https"
+                        needs_auth = False
+
+                    router_name = f"vnc-{vm_id_short}"
+                    middlewares = [f"vnc-strip-{vm_id_short}"]
+
+                    labels.update({
+                        "traefik.enable": "true",
+                        "traefik.docker.network": "traefik-routing",
+                        f"traefik.http.services.{router_name}.loadbalancer.server.port": vnc_port,
+                        f"traefik.http.services.{router_name}.loadbalancer.server.scheme": vnc_scheme,
+                        f"traefik.http.routers.{router_name}.rule": f"PathPrefix(`/vnc/{vm.id}`)",
+                        f"traefik.http.routers.{router_name}.entrypoints": "web",
+                        f"traefik.http.routers.{router_name}.service": router_name,
+                        f"traefik.http.middlewares.vnc-strip-{vm_id_short}.stripprefix.prefixes": f"/vnc/{vm.id}",
+                    })
+
+                    if vnc_scheme == "https":
+                        labels[f"traefik.http.services.{router_name}.loadbalancer.serverstransport"] = "vnc-insecure@file"
+                        if not needs_auth:
+                            middlewares.append("vnc-headers")
+                            labels[f"traefik.http.middlewares.vnc-headers.headers.customrequestheaders.Authorization"] = "Basic a2FzbV91c2VyOnBhc3N3b3Jk"
+
+                    labels[f"traefik.http.routers.{router_name}.middlewares"] = ",".join(middlewares)
+
                 if template.os_type == "windows":
PATCHEOF

        # Try to apply patch, fall back to manual fix if it fails
        if ! patch -p1 < /tmp/vnc-fix.patch 2>/dev/null; then
            warn "Patch failed, applying fix manually..."
            # The fix will be applied via Python script instead
            python3 << 'PYEOF'
import re

with open('backend/cyroid/api/ranges.py', 'r') as f:
    content = f.read()

# Check if already fixed
if 'traefik.enable' in content:
    print("Fix already applied")
    exit(0)

old_code = '''                labels = {
                    "cyroid.range_id": str(range_id),
                    "cyroid.vm_id": str(vm.id),
                    "cyroid.hostname": vm.hostname,
                }

                if template.os_type == "windows":'''

new_code = '''                vm_id_short = str(vm.id)[:8]
                labels = {
                    "cyroid.range_id": str(range_id),
                    "cyroid.vm_id": str(vm.id),
                    "cyroid.hostname": vm.hostname,
                }

                # Add traefik labels for VNC web console routing
                display_type = vm.display_type or "desktop"
                if display_type == "desktop":
                    base_image = template.base_image or ""
                    is_linuxserver = "linuxserver/" in base_image or "lscr.io/linuxserver" in base_image
                    is_kasmweb = "kasmweb/" in base_image

                    if base_image.startswith("iso:") or template.os_type == "windows":
                        vnc_port = "8006"
                        vnc_scheme = "http"
                        needs_auth = False
                    elif is_linuxserver:
                        vnc_port = "3000"
                        vnc_scheme = "http"
                        needs_auth = False
                    elif is_kasmweb:
                        vnc_port = "6901"
                        vnc_scheme = "https"
                        needs_auth = True
                    else:
                        vnc_port = "6901"
                        vnc_scheme = "https"
                        needs_auth = False

                    router_name = f"vnc-{vm_id_short}"
                    middlewares = [f"vnc-strip-{vm_id_short}"]

                    labels.update({
                        "traefik.enable": "true",
                        "traefik.docker.network": "traefik-routing",
                        f"traefik.http.services.{router_name}.loadbalancer.server.port": vnc_port,
                        f"traefik.http.services.{router_name}.loadbalancer.server.scheme": vnc_scheme,
                        f"traefik.http.routers.{router_name}.rule": f"PathPrefix(`/vnc/{vm.id}`)",
                        f"traefik.http.routers.{router_name}.entrypoints": "web",
                        f"traefik.http.routers.{router_name}.service": router_name,
                        f"traefik.http.middlewares.vnc-strip-{vm_id_short}.stripprefix.prefixes": f"/vnc/{vm.id}",
                    })

                    if vnc_scheme == "https":
                        labels[f"traefik.http.services.{router_name}.loadbalancer.serverstransport"] = "vnc-insecure@file"
                        if not needs_auth:
                            middlewares.append("vnc-headers")
                            labels[f"traefik.http.middlewares.vnc-headers.headers.customrequestheaders.Authorization"] = "Basic a2FzbV91c2VyOnBhc3N3b3Jk"

                    labels[f"traefik.http.routers.{router_name}.middlewares"] = ",".join(middlewares)

                if template.os_type == "windows":'''

if old_code in content:
    content = content.replace(old_code, new_code)
    with open('backend/cyroid/api/ranges.py', 'w') as f:
        f.write(content)
    print("Fix applied successfully")
else:
    print("Could not find code to patch")
    exit(1)
PYEOF
        fi
        rm -f /tmp/vnc-fix.patch
    else
        log "VNC routing fix already applied"
    fi

    # ----------------------------
    # Step 4: Create Data Directories
    # ----------------------------
    log "Creating data directories..."

    # Use platform-appropriate data directory
    if [ "$OS_TYPE" == "Darwin" ]; then
        # macOS: use user's Library folder (no sudo needed)
        CYROID_DATA_DIR="$HOME/Library/Application Support/cyroid"
        mkdir -p "$CYROID_DATA_DIR"/{iso-cache,template-storage,vm-storage,shared}

        # Patch CYROID's docker-compose.yml to use macOS paths
        log "Patching CYROID for macOS paths..."
        if [ -f docker-compose.yml ]; then
            # Use Python for reliable path replacement (handles spaces in path)
            python3 -c "
import sys
path = sys.argv[1]
with open('docker-compose.yml', 'r') as f:
    content = f.read()
content = content.replace('/data/cyroid', path)
with open('docker-compose.yml', 'w') as f:
    f.write(content)
" "$CYROID_DATA_DIR"
            log "Patched docker-compose.yml for macOS"
        fi
    else
        # Linux: use /data/cyroid (requires sudo)
        CYROID_DATA_DIR="/data/cyroid"
        sudo mkdir -p "$CYROID_DATA_DIR"/{iso-cache,template-storage,vm-storage,shared}
        sudo chown -R $USER:$USER "$CYROID_DATA_DIR"
    fi
    export CYROID_DATA_DIR
    log "Data directory: $CYROID_DATA_DIR"

    # ----------------------------
    # Step 5: Setup Environment
    # ----------------------------
    log "Setting up environment..."

    if [ ! -f .env ]; then
        cp .env.example .env 2>/dev/null || {
            # Create minimal .env if example doesn't exist
            cat > .env << 'ENVEOF'
# CYROID Environment Configuration
DATABASE_URL=postgresql://cyroid:cyroid@db:5432/cyroid
REDIS_URL=redis://redis:6379/0
ENVEOF
        }
        log "Created .env"
    else
        log ".env already exists, keeping existing config"
    fi

    # ----------------------------
    # Step 6: Start CYROID
    # ----------------------------
    log "Starting CYROID services..."

    docker compose up -d

    # Wait for services
    log "Waiting for services to start..."

    # Wait for API to be ready (via Traefik at port 80)
    # Check if API responds with any valid HTTP code (not 502/503/000)
    MAX_WAIT=120
    WAITED=0
    while true; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/v1/auth/login 2>/dev/null)
        if [[ "$HTTP_CODE" =~ ^[1-4] ]]; then
            break  # Got a valid response (1xx-4xx means API is up)
        fi
        if [ $WAITED -ge $MAX_WAIT ]; then
            error "CYROID API didn't start within ${MAX_WAIT}s. Check logs: docker compose logs api"
        fi
        sleep 2
        WAITED=$((WAITED + 2))
        echo -ne "\r  Waiting for API... ${WAITED}s"
    done
    echo ""
    log "API is ready"

    # API URL via Traefik
    API_URL="http://localhost/api/v1"

    # ----------------------------
    # Step 7: Create Admin User
    # ----------------------------
    log "Creating admin user..."

    # Try to register (will fail if user exists, that's OK)
    REGISTER_RESP=$(curl -s -X POST "${API_URL}/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${ADMIN_USER}\",\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" 2>&1) || true

    if echo "$REGISTER_RESP" | grep -q '"id"'; then
        log "Admin user created: ${ADMIN_USER}"
    elif echo "$REGISTER_RESP" | grep -qi "already\|exists"; then
        log "Admin user already exists"
    else
        warn "Registration response: $REGISTER_RESP"
    fi

    # Approve admin user (required for login)
    docker compose exec -T db psql -U cyroid -d cyroid -c \
        "UPDATE users SET is_approved = true, role = 'ADMIN' WHERE username = '${ADMIN_USER}';" > /dev/null 2>&1

    # Return to script directory
    cd "$SCRIPT_DIR"

fi  # End local setup

# ----------------------------
# Step 8: Get Auth Token
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
# Step 9: Build Lab Images
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
# Step 10: Import to CYROID
# ----------------------------
log "Importing Red Team Lab to CYROID..."

export CYROID_API_URL="$API_URL"
export CYROID_TOKEN="$TOKEN"

cd "$SCRIPT_DIR/scenarios/red-team-lab"

# First import templates only
if [ "$DEPLOY_MODE" == "local" ]; then
    python3 deploy/import-to-cyroid.py --local --templates-only --dc-type "$DC_TYPE"
else
    python3 deploy/import-to-cyroid.py --templates-only --dc-type "$DC_TYPE"
fi

# Create ranges for each student
log "Creating $NUM_STUDENTS student environment(s)..."
for i in $(seq 1 $NUM_STUDENTS); do
    if [ "$NUM_STUDENTS" -eq 1 ]; then
        RANGE_NAME="Red Team Training Lab"
    else
        RANGE_NAME="Red Team Lab - Student $i"
    fi

    # Each student gets a different subnet (172.16.x for student 1, 172.17.x for student 2, etc.)
    SUBNET_OFFSET=$((i - 1))

    echo ""
    log "Creating range: $RANGE_NAME (subnet: 172.$((16 + SUBNET_OFFSET)).x.x)"
    if [ "$DEPLOY_MODE" == "local" ]; then
        python3 deploy/import-to-cyroid.py --local --range-name "$RANGE_NAME" --subnet-offset $SUBNET_OFFSET --dc-type "$DC_TYPE"
    else
        python3 deploy/import-to-cyroid.py --range-name "$RANGE_NAME" --subnet-offset $SUBNET_OFFSET --dc-type "$DC_TYPE"
    fi
done

# ----------------------------
# Done!
# ----------------------------
echo ""
echo "=============================================="
echo -e "${GREEN}   Setup Complete!${NC}"
echo "=============================================="
echo ""

echo "Created $NUM_STUDENTS student environment(s)"
echo ""

if [ "$DEPLOY_MODE" == "local" ]; then
    echo "CYROID Platform: $CYROID_DIR"
    echo "CYROID UI:       http://localhost"
    echo "Admin User:      ${ADMIN_USER}"
    echo "Admin Pass:      ${ADMIN_PASS}"
    echo ""
    echo "Next Steps:"
    echo "  1. Open http://localhost in your browser"
    echo "  2. Login with credentials above"
    echo "  3. Go to Ranges and select a student lab"
    echo "  4. Click 'Deploy' to start the environment"
    echo ""
    echo "To add more student environments later:"
    echo "  export CYROID_API_URL=http://localhost/api/v1"
    echo "  export CYROID_TOKEN=${TOKEN}"
    echo "  python3 scenarios/red-team-lab/deploy/import-to-cyroid.py --local --range-name 'Student N' --subnet-offset N"
else
    echo "Remote CYROID: ${API_URL}"
    echo ""
    echo "Next Steps:"
    echo "  1. Open your CYROID instance in a browser"
    echo "  2. Login with your credentials"
    echo "  3. Go to Ranges and select a student lab"
    echo "  4. Click 'Deploy' to start the environment"
    echo ""
    echo "To add more student environments later:"
    echo "  export CYROID_API_URL=${API_URL}"
    echo "  export CYROID_TOKEN=${TOKEN}"
    echo "  python3 scenarios/red-team-lab/deploy/import-to-cyroid.py --range-name 'Student 2'"
fi
echo ""
