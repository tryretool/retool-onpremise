# Retool Kubernetes Deployment

This directory contains Kubernetes manifests for deploying Retool in two configurations:

## Quick Start

1. **Set your version** in `versions.env`:
   ```bash
   RETOOL_VERSION=3.148.27-stable
   ```

2. **Deploy**:
   ```bash
   # Standard Retool deployment
   ./retool-apply.sh
   
   # Retool with local Temporal cluster
   ./retool-apply.sh --with-temporal
   ```

## Deployment Options

### Standard Deployment
- Standard setup

```bash
./retool-apply.sh
```

### Temporal Deployment  
- Includes local Temporal cluster

```bash
./retool-apply.sh --with-temporal
```

## Configuration Files

- `versions.env` - Set Retool versions here
- `retool-config.yaml` - Environment variables for standard deployment
- `retool-secrets.template.yaml` - Template for secrets (copy and customize)
- `temporal/` - Local Temporal cluster dependencies (deployed with --with-temporal)

## Advanced Usage

```bash
# Deploy specific components
./retool-apply.sh retool-container.yaml
./retool-apply.sh --with-temporal temporal/
