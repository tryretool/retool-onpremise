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
 
# Add AppArmor profile if using Ubuntu 24.04 or newer
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID}" = "ubuntu" ] && command -v dpkg &> /dev/null; then
        if dpkg --compare-versions "${VERSION_ID}" ge "24.04"; then
            echo "  Ubuntu ${VERSION_ID} detected. Setting up AppArmor profile for nsjail..."
            if ! dpkg -s apparmor-profiles &> /dev/null; then
                sudo apt-get update -y > /dev/null 2>&1 || true
                sudo apt-get install -y apparmor-profiles > /dev/null 2>&1 || true
            fi
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [ -f "${SCRIPT_DIR}/appArmor/usr.bin.nsjail" ]; then
                sudo cp "${SCRIPT_DIR}/appArmor/usr.bin.nsjail" /etc/apparmor.d/usr.bin.nsjail
                sudo apparmor_parser /etc/apparmor.d/usr.bin.nsjail || true
                echo "  ✅ AppArmor profile for nsjail installed"
            else
                echo "  ⚠️ Could not find appArmor/usr.bin.nsjail; skipping AppArmor profile setup"
            fi
        fi
    fi
fi

# Install the customized docker-default AppArmor profile + systemd drop-in
# so it survives docker restarts. The script handles its own preflight
# (skips silently on hosts without AppArmor); --check tells us whether any
# persistent changes are needed so we only prompt the user when there's
# actually work to do.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPARMOR_SCRIPT="${SCRIPT_DIR}/scripts/setup-docker-apparmor.sh"
if [ -x "$APPARMOR_SCRIPT" ]; then
    if "$APPARMOR_SCRIPT" --check; then
        echo "  ✅ docker-default AppArmor profile already configured (or not applicable on this host)."
    else
        echo ""
        echo "  Agent-sandbox needs the bundled docker-default AppArmor profile installed."
        echo "  The script will:"
        echo "    - copy appArmor/docker-default to /etc/apparmor.d/docker-default"
        echo "    - load it into the kernel via 'apparmor_parser -r'"
        echo "    - install a systemd drop-in at"
        echo "      /etc/systemd/system/docker.service.d/retool-apparmor.conf so the"
        echo "      profile is re-applied on every docker.service start"
        echo "  Requires sudo. See appArmor/README.md for details."
        read -p "  Run it now? [Y/n]: " apparmor_confirm
        case "${apparmor_confirm:-y}" in
            [yY]|[yY][eE][sS])
                "$APPARMOR_SCRIPT" || \
                    echo "  ⚠️ docker-default AppArmor setup failed; agent-sandbox may not work. See appArmor/README.md for manual steps."
                ;;
            *)
                echo "  ⏭️  Skipped docker-default AppArmor setup."
                echo "  ⚠️ Agent-sandbox will fail with apparmor=\"DENIED\" errors until you run"
                echo "     '${APPARMOR_SCRIPT}' manually."
                ;;
        esac
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

postgres_password=$(random 64)

ae_private_pem=$(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2>/dev/null)
ae_public_pem=$(echo "$ae_private_pem" | openssl ec -pubout 2>/dev/null)
ae_private_key=$(echo "$ae_private_pem" | awk '{if(NR>1)printf "\\n";printf "%s",$0}')
ae_public_key=$(echo "$ae_public_pem" | awk '{if(NR>1)printf "\\n";printf "%s",$0}')

cat << EOF > docker.env
# Environment variables reference: docs.retool.com/docs/environment-variables
DEPLOYMENT_TEMPLATE_TYPE=docker-compose

# Retool's internal Postgres credentials
POSTGRES_HOST=postgres
POSTGRES_DB=hammerhead_production
POSTGRES_PORT=5432
POSTGRES_USER=retool_internal_user
POSTGRES_PASSWORD=$postgres_password

# Retool DB credentials
RETOOLDB_POSTGRES_HOST=retooldb-postgres
RETOOLDB_POSTGRES_DB=postgres
RETOOLDB_POSTGRES_PORT=5432
RETOOLDB_POSTGRES_USER=root
RETOOLDB_POSTGRES_PASSWORD=$(random 64)

# Workflows configuration
WORKFLOW_BACKEND_HOST=http://workflows-backend:3000
CODE_EXECUTOR_INGRESS_DOMAIN=http://code-executor:3004
JS_EXECUTOR_INGRESS_DOMAIN=http://js-executor:3000

# Agent sandbox configuration
AGENT_EXECUTOR_ENABLED=true
RR_AGENT_PUBSUB_BACKEND=postgres
AGENT_EXECUTOR_CONTROLLER_INGRESS_DOMAIN=http://agent-sandbox-controller:3018
AGENT_EXECUTOR_PROXY_INGRESS_DOMAIN=http://agent-sandbox-proxy:3019
AGENT_EXECUTOR_FRONTEND_WS_PROXY_DOMAIN=http://$hostname:3019
AGENT_EXECUTOR_JWT_PRIVATE_KEY="$ae_private_key"
AGENT_EXECUTOR_JWT_PUBLIC_KEY="$ae_public_key"
AGENT_EXECUTOR_ENCRYPTION_KEY=$(openssl rand -hex 32)
STATE_BACKEND=postgres
AGENT_EXECUTOR_POSTGRES_URL=postgres://retool_internal_user:$postgres_password@postgres:5432/hammerhead_production
AGENT_EXECUTOR_POSTGRES_SCHEMA=agent_executor

# S3-compatible storage (MinIO)
AWS_ENDPOINT_URL=http://minio:9000
RR_GIT_S3_BUCKET=retool-rr-git
RR_GIT_S3_ACCESS_KEY_ID=retool
RR_GIT_S3_SECRET_ACCESS_KEY=retoolminio
RR_GIT_S3_REGION=us-east-1
RR_SNAPSHOTS_S3_BUCKET=retool-rr-snapshots
RR_SNAPSHOTS_S3_ACCESS_KEY_ID=retool
RR_SNAPSHOTS_S3_SECRET_ACCESS_KEY=retoolminio
RR_SNAPSHOTS_S3_REGION=us-east-1
RR_SNAPSHOTS_S3_ENDPOINT=http://minio:9000

# Comment out below to use Retool-managed Temporal (Enterprise license)
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
BASE_DOMAIN=https://$hostname

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
