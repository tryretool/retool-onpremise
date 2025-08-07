#!/bin/bash
# Lightweight Retool Deployment Script
set -e

# Configuration
VERSION_FILE="versions.env"
DEFAULT_VERSION="X.Y.Z"
WITH_TEMPORAL=false

usage() {
    echo "Usage: $0 [OPTIONS] [target]"
    echo ""
    echo "Options:"
    echo "  --with-temporal    Deploy with local Temporal cluster"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Arguments:"
    echo "  target: File or directory to deploy (defaults to current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                                # Deploy standard Retool"
    echo "  $0 --with-temporal                # Deploy Retool with local Temporal cluster"
    echo "  $0 retool-container.yaml          # Deploy single file"
    echo "  $0 --with-temporal temporal/      # Deploy only local Temporal components"
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

apply_with_version() {
    local file="$1"
    sed "s|tryretool/backend:$DEFAULT_VERSION|tryretool/backend:$RETOOL_VERSION|g; s|tryretool/code-executor-service:$DEFAULT_VERSION|tryretool/code-executor-service:$RETOOL_VERSION|g" "$file" | kubectl apply -f -
}

deploy() {
    local target=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-temporal)
                WITH_TEMPORAL=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done
    
    # Default target
    target=${target:-.}
    [[ -e "$target" ]] || error "Target '$target' does not exist"
    command -v kubectl >/dev/null || error "kubectl not found"
    
    load_version
    
    if $WITH_TEMPORAL; then
        echo "Deploying Retool with local Temporal cluster..."
    else
        echo "Deploying standard Retool..."
    fi
    
    # Deploy config dependencies
    if ! $WITH_TEMPORAL && [[ -f "retool-config.yaml" ]]; then
        kubectl apply -f retool-config.yaml
    fi
    
    # Deploy local Temporal cluster first if needed
    if $WITH_TEMPORAL && [[ -d "temporal" ]] && [[ "$target" != "temporal/"* ]]; then
        echo "Deploying local Temporal cluster dependencies..."
        find temporal/ -name "*.yaml" -exec kubectl apply -f {} \;
    fi
    
    # Deploy main resources
    if [[ -f "$target" ]]; then
        # Single file
        if $WITH_TEMPORAL && [[ "$target" == *temporal* ]]; then
            # Temporal files don't need version replacement
            kubectl apply -f "$target"
        else
            apply_with_version "$target"
        fi
    else
        # Directory
        local exclude_temporal=""
        if ! $WITH_TEMPORAL; then
            exclude_temporal="-not -path '*/temporal/*'"
        fi
        
        eval "find '$target' -name '*.yaml' -not -name 'retool-config.yaml' -not -name '$VERSION_FILE' $exclude_temporal" | while read -r file; do
            if [[ "$file" == *temporal* ]]; then
                # Temporal files don't need version replacement
                kubectl apply -f "$file"
            else
                apply_with_version "$file"
            fi
        done
    fi
    
    echo "Deployment completed! 🚀"
}

# Run deployment
deploy "$@"
