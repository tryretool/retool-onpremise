#!/bin/bash

# Apply the agent sandbox's docker-default AppArmor profile if this host doesn't have it yet.
# Same check install.sh runs; see appArmor/README.md.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPARMOR_SCRIPT="${SCRIPT_DIR}/scripts/setup-docker-apparmor.sh"
if [ -x "$APPARMOR_SCRIPT" ] && ! "$APPARMOR_SCRIPT" --check; then
    echo "Agent-sandbox needs the bundled docker-default AppArmor profile installed. Requires sudo. See appArmor/README.md for details."
    read -p "Run it now? [Y/n]: " apparmor_confirm
    case "${apparmor_confirm:-y}" in
        [yY]|[yY][eE][sS])
            if ! "$APPARMOR_SCRIPT"; then
                echo "⚠️ docker-default AppArmor setup failed; agent-sandbox may not work. See appArmor/README.md for manual steps."
            fi
            ;;
        *)
            echo "⚠️ Skipped. Agent-sandbox will fail with apparmor=\"DENIED\" errors until you run '${APPARMOR_SCRIPT}'."
            ;;
    esac
fi

echo "Downloading and building new images..."
docker compose build

echo "Bringing up new containers to replace existing ones..."
docker compose up -d

# Compose doesn't replace sandbox containers. Removing them first lets the prune delete their image.
echo "Removing old agent sandbox containers..."
docker ps -aq --filter label=com.retool.agent-executor.role=sandbox | xargs -r docker rm -f

echo "Removing unused images..."
docker image prune -a -f
