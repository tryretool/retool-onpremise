#!/bin/bash
# Lightweight Retool Deployment Script
set -e

# Configuration
VERSION_FILE="versions.env"
DEFAULT_VERSION="X.Y.Z"

usage() {
    echo "Usage: $0 [target]"
    echo "  target: File or directory to deploy (defaults to current directory)"
    echo ""
    echo "Edit '$VERSION_FILE' to set the version"
    exit 1
}

error() {
    echo "ERROR: $1" >&2
    exit 1
}

load_version() {
    [[ -f "$VERSION_FILE" ]] || error "Version file '$VERSION_FILE' not found"
    source "$VERSION_FILE"
    [[ -n "$RETOOL_VERSION" ]] || error "RETOOL_VERSION not set in $VERSION_FILE"
    [[ "$RETOOL_VERSION" != "X.Y.Z-stable" ]] || error "RETOOL_VERSION is still set to default 'X.Y.Z-stable'. Please update it in $VERSION_FILE"
    echo "Using version: $RETOOL_VERSION"
}

deploy() {
    local target=${1:-.}
    [[ -e "$target" ]] || error "Target '$target' does not exist"
    command -v kubectl >/dev/null || error "kubectl not found"
    
    load_version
    
    echo "Deploying Retool resources..."
    
    [[ -f "retool-config.yaml" ]] && kubectl apply -f retool-config.yaml
    
    if [[ -f "$target" ]]; then
        sed "s|tryretool/backend:$DEFAULT_VERSION|tryretool/backend:$RETOOL_VERSION|g; s|tryretool/code-executor-service:$DEFAULT_VERSION|tryretool/code-executor-service:$RETOOL_VERSION|g" "$target" | kubectl apply -f -
    else
        find "$target" -name "*.yaml" -not -name "retool-config.yaml" -not -name "$VERSION_FILE" -exec sed "s|tryretool/backend:$DEFAULT_VERSION|tryretool/backend:$RETOOL_VERSION|g; s|tryretool/code-executor-service:$DEFAULT_VERSION|tryretool/code-executor-service:$RETOOL_VERSION|g" {} \; | kubectl apply -f -
    fi
    
    echo "Deployment completed! 🚀"
}

# Show help or deploy
[[ "$1" == "-h" || "$1" == "--help" ]] && usage
deploy "$@"
