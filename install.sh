#!/bin/bash

echo ""
echo "Checking installation requirements..."
if grep Ubuntu /etc/issue &> /dev/null; then
    echo "  ✅ Running on Ubuntu"
else
    echo "  ⚠️ This script is supported on Ubuntu, other distros may need Docker and Docker Compose installed manually"
fi

if command -v docker &> /dev/null; then
    echo "  ✅ Docker is installed: $(docker --version)"
    
    if docker compose version &> /dev/null; then
        echo "  ✅ Docker Compose plugin is installed: $(docker compose version)"
    else
        echo "  ❌ Docker Compose plugin is not installed."
        echo "   You can install it following the instructions at: https://docs.docker.com/compose/install"
        exit 1
    fi
else
    echo "  Docker is not yet installed"
    if command -v wget &> /dev/null; then
        echo "  ✅ wget is installed"
    else
        echo "  ❌ wget not installed, needed to download Docker's install script"
        exit 1
    fi
    echo "  Attempting to run Docker's install script (https://get.docker.com)..."
    wget -qO- https://get.docker.com/ | sh
    echo "  Rechecking Docker and Docker Compose..."
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        echo "  ❌ Docker or Docker Compose plugin still not installed"
        echo "  See Docker docs (https://docs.docker.com/install) to install manually before rerunning this script"
        exit 1
    else
        echo "  ✅ Docker is installed: $(docker --version)"
        echo "  ✅ Docker Compose plugin is installed: $(docker compose version)"
    fi
fi

echo ""

[[ -f docker.env ]] && echo "⚠️ docker.env file already exists, skipping initializing it!" && exit 1

echo "Prompting for optional configuration..."

read -p "  Retool license key: " licenseKey
licenseKey=${licenseKey:-EXPIRED-LICENSE-KEY-TRIAL}

read -p "  Domain (e.g. retool.company.com) pointing to this server: " hostname
hostname=${hostname:-$(dig +short myip.opendns.com @resolver1.opendns.com)}
echo ""

# Create docker.env with values

random() { cat /dev/urandom | base64 | head -c "$1" | tr -d +/ ; }

cat << EOF > docker.env
# Environment variables reference: docs.retool.com/docs/environment-variables
DEPLOYMENT_TEMPLATE_TYPE=docker-compose

# Retool's internal Postgres credentials
POSTGRES_HOST=postgres
POSTGRES_DB=hammerhead_production
POSTGRES_PORT=5432
POSTGRES_USER=retool_internal_user
POSTGRES_PASSWORD=$(random 64)

# Retool DB credentials
RETOOLDB_POSTGRES_HOST=retooldb-postgres
RETOOLDB_POSTGRES_DB=postgres
RETOOLDB_POSTGRES_PORT=5432
RETOOLDB_POSTGRES_USER=root
RETOOLDB_POSTGRES_PASSWORD=$(random 64)

# Workflows configuration
WORKFLOW_BACKEND_HOST=http://workflows-backend:3000
CODE_EXECUTOR_INGRESS_DOMAIN=http://code-executor:3004

# See Temporal options: https://docs.retool.com/self-hosted/concepts/temporal#compare-options
WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_HOST=temporal
WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_PORT=7233

# Key to encrypt/decrypt sensitive values stored in the Postgres database
ENCRYPTION_KEY=$(random 64)

# Key to sign requests for authentication with Retool's backend API server
JWT_SECRET=$(random 256)

# License you received from my.retool.com or your Retool contact
LICENSE_KEY=$licenseKey

# Make sure $hostname is your domain to set up HTTPS (e.g. retool.company.com)
DOMAINS=$hostname -> http://api:3000

# Used to create links like user invitations and password resets
# Retool tries to guess this, but it can be incorrect if using a proxy in front of the instance
# BASE_DOMAIN=https://retool.company.com

# If your domain/HTTPS isn't in place yet
# COOKIE_INSECURE=true
EOF

echo "✅ Created docker.env"

# Pull Retool DB config from docker.env if retooldb.env doesn't exist 

[[ -f retooldb.env ]] || grep RETOOLDB docker.env | cut -c 10- > retooldb.env && echo "✅ Created retooldb.env"

# Next steps

echo ""
echo "Done! Check docker.env and retooldb.env files for expected values, and confirm"
echo "the Retool version in Dockerfile. We suggest the most recent X.Y.Z-stable version,"
echo "see Dockerhub for available tags: https://hub.docker.com/r/tryretool/backend/tags"
echo ""
