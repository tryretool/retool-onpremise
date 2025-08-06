#!/usr/bin/env bash

# Simple apply script that checks versions before kubectl apply
# Usage: ./apply.sh [kubernetes-file-or-directory]

set -e

INPUT_PATH=${1:-.}

echo "🚀 Retool Kubernetes Deployment"
echo "================================"

if [ ! -e "$INPUT_PATH" ]; then
    echo "❌ Error: $INPUT_PATH does not exist."
    exit 1
fi

# Check versions first
echo "🔍 Checking image versions..."
all_versions=()
yaml_files=()

if [ -d "$INPUT_PATH" ]; then
    # Directory: find all YAML files
    while IFS= read -r -d '' file; do
        yaml_files+=("$file")
    done < <(find "$INPUT_PATH" -name "*.yaml" -print0)
elif [ -f "$INPUT_PATH" ]; then
    yaml_files+=("$INPUT_PATH")
else
    echo "❌ Error: $INPUT_PATH is not a file or directory"
    exit 1
fi

for file in "${yaml_files[@]}"; do
    while IFS= read -r line; do
        if [[ $line =~ image:[[:space:]]*tryretool/(backend|code-executor-service): ]]; then
            version=$(echo "$line" | sed -n 's/.*:\([^[:space:]]*\)/\1/p')
            all_versions+=("$version")
        fi
    done < "$file"
done

unique_versions=($(printf "%s\n" "${all_versions[@]}" | sort -u))
issues=0

if [ ${#unique_versions[@]} -eq 0 ]; then
    echo "❌ No tryretool backend or code-executor images found in manifests!"
    exit 1
elif [ ${#unique_versions[@]} -eq 1 ]; then
    if [[ "${unique_versions[0]}" == "X.Y.Z" ]]; then
        echo "❌ All versions are set to placeholder (X.Y.Z) - please set a version!"
        issues=1
    else
        echo "✅ All services use version: ${unique_versions[0]}"
    fi
else
    echo "⚠️  Found multiple versions in use across services:"
    for v in "${unique_versions[@]}"; do
        echo "  - $v"
    done
    issues=1
fi

echo ""

if [ $issues -eq 1 ]; then
    read -p "⚠️  Continue with deployment anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        exit 1
    fi
    echo "⚠️  Proceeding with deployment (may fail)..."
    echo ""
fi

echo "📦 Applying Kubernetes manifests..."

if [ -d "$INPUT_PATH" ]; then
    kubectl apply -f "$INPUT_PATH" -R
else
    kubectl apply -f "$INPUT_PATH"
fi

echo ""
echo "✅ Deployment completed!"
echo "📊 Check status: kubectl get pods"
