#!/bin/bash
# Build and optionally push Red Team Lab container images

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$SCRIPT_DIR/../containers"

# Default: no registry prefix for local builds
# Set REGISTRY env var or use -r flag for remote registry
REGISTRY="${REGISTRY:-}"
TAG="${TAG:-latest}"

usage() {
    cat <<EOF
Build Red Team Lab container images

Usage: $0 [options] [command]

Commands:
    build       Build all images locally
    push        Push images to registry
    all         Build and push

Options:
    -r, --registry REGISTRY    Container registry (required for push)
    -t, --tag TAG              Image tag (default: $TAG)
    -h, --help                 Show this help

Examples:
    $0 build                                    # Build locally (no registry prefix)
    $0 -r docker.io/myuser build               # Build with registry prefix
    $0 -r docker.io/myuser push                # Push to Docker Hub
    $0 -r ghcr.io/myorg -t v1.0 all           # Build and push with tag
EOF
    exit 1
}

# Helper to get full image name (with or without registry)
get_image_name() {
    local name="$1"
    if [ -n "$REGISTRY" ]; then
        echo "$REGISTRY/$name:$TAG"
    else
        echo "$name:$TAG"
    fi
}

build_images() {
    echo "=== Building Red Team Lab Images ==="
    if [ -n "$REGISTRY" ]; then
        echo "Registry: $REGISTRY"
    else
        echo "Registry: (local, no prefix)"
    fi
    echo "Tag: $TAG"
    echo ""

    # WordPress (SQLi target)
    echo "[1/3] Building WordPress image..."
    docker build -t "$(get_image_name redteam-lab-wordpress)" "$CONTAINERS_DIR/wordpress/"

    # File Server
    echo "[2/3] Building File Server image..."
    docker build -t "$(get_image_name redteam-lab-fileserver)" "$CONTAINERS_DIR/fileserver/"

    # Workstation (BeEF victim)
    echo "[3/3] Building Workstation image..."
    docker build -t "$(get_image_name redteam-lab-workstation)" "$CONTAINERS_DIR/workstation/"

    echo ""
    echo "=== Build Complete ==="
    docker images | grep redteam-lab
}

push_images() {
    if [ -z "$REGISTRY" ]; then
        echo "ERROR: Registry is required for push. Use -r flag to specify."
        exit 1
    fi

    echo "=== Pushing Red Team Lab Images ==="
    echo "Registry: $REGISTRY"
    echo "Tag: $TAG"
    echo ""

    docker push "$(get_image_name redteam-lab-wordpress)"
    docker push "$(get_image_name redteam-lab-fileserver)"
    docker push "$(get_image_name redteam-lab-workstation)"

    echo ""
    echo "=== Push Complete ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        build|push|all)
            COMMAND="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

case "${COMMAND:-build}" in
    build)
        build_images
        ;;
    push)
        push_images
        ;;
    all)
        build_images
        push_images
        ;;
    *)
        usage
        ;;
esac
