#!/bin/bash
# Build and optionally push Red Team Lab container images

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$SCRIPT_DIR/../containers"

# Default registry (change this to your registry)
REGISTRY="${REGISTRY:-ghcr.io/your-org}"
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
    -r, --registry REGISTRY    Container registry (default: $REGISTRY)
    -t, --tag TAG              Image tag (default: $TAG)
    -h, --help                 Show this help

Examples:
    $0 build                                    # Build locally
    $0 -r docker.io/myuser push                # Push to Docker Hub
    $0 -r ghcr.io/myorg -t v1.0 all           # Build and push with tag
EOF
    exit 1
}

build_images() {
    echo "=== Building Red Team Lab Images ==="
    echo "Registry: $REGISTRY"
    echo "Tag: $TAG"
    echo ""

    # WordPress (SQLi target)
    echo "[1/3] Building WordPress image..."
    docker build -t "$REGISTRY/redteam-lab-wordpress:$TAG" "$CONTAINERS_DIR/wordpress/"

    # File Server
    echo "[2/3] Building File Server image..."
    docker build -t "$REGISTRY/redteam-lab-fileserver:$TAG" "$CONTAINERS_DIR/fileserver/"

    # Workstation (BeEF victim)
    echo "[3/3] Building Workstation image..."
    docker build -t "$REGISTRY/redteam-lab-workstation:$TAG" "$CONTAINERS_DIR/workstation/"

    echo ""
    echo "=== Build Complete ==="
    docker images | grep redteam-lab
}

push_images() {
    echo "=== Pushing Red Team Lab Images ==="
    echo "Registry: $REGISTRY"
    echo "Tag: $TAG"
    echo ""

    docker push "$REGISTRY/redteam-lab-wordpress:$TAG"
    docker push "$REGISTRY/redteam-lab-fileserver:$TAG"
    docker push "$REGISTRY/redteam-lab-workstation:$TAG"

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
