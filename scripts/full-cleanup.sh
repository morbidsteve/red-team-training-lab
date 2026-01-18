#!/bin/bash
# Full Cleanup Script - Wrapper for cleanup.sh --full --force
#
# This script is kept for backwards compatibility.
# Use cleanup.sh --full directly for more options.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../cleanup.sh" --full --force "$@"
