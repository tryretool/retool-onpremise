# Retool Kubernetes Deployment

This repository contains Kubernetes manifests for deploying Retool on-premise. See [our docs](https://docs.retool.com/self-hosted/tutorials/kubernetes/manifests) for more details.

## Quick Start

Choose your deployment option:

### Option 1: Retool Only
```bash
cd kubernetes/base
../apply.sh .
```

### Option 2: Retool + Temporal (for Workflows)
```bash
cd kubernetes/base-with-temporal
../apply.sh .
```

## What's Included

### `kubernetes/base/` - Retool Only
- Retool backend API
- Code executor service
- Jobs runner
- PostgreSQL database
- Workflows backend and worker

### `kubernetes/base-with-temporal/` - Retool + Temporal
- Everything from `base/` plus:
- Complete Temporal cluster for workflow orchestration

## Before Deploying

1. **Set your Retool version** in the manifests:
   ```bash
   # Replace X.Y.Z with actual version (e.g., 2.123.4-stable)
   ```

2. **Configure secrets** in `retool-secrets.template.yaml`:
   - Replace placeholder values with actual base64-encoded secrets
   - Or create a proper secrets file

## Available Versions

Check available Retool versions at:
- https://hub.docker.com/r/tryretool/backend/tags
- https://hub.docker.com/r/tryretool/code-executor-service/tags

## What the apply.sh script does

- ✅ Checks if all services use the same version
- ❌ Warns about placeholder `X.Y.Z` versions
- 🤔 Asks for confirmation if issues are found
- 🚀 Runs `kubectl apply` with your manifests

## After Deployment

Check your deployment:
```bash
kubectl get pods
kubectl get services
``` 