#!/bin/bash

# docker.env must carry the Garage settings this compose file boots with.
# install.sh writes them on fresh installs; docs/migrate-blob-storage.md
# migrates older files.
[[ -f docker.env ]] || {
    echo "⛔ docker.env not found — run ./upgrade.sh from your deployment directory."
    exit 1
}

missing=()
for v in GARAGE_DEFAULT_BUCKET GARAGE_DEFAULT_ACCESS_KEY GARAGE_DEFAULT_SECRET_KEY GARAGE_RPC_SECRET; do
    grep -q "^$v=." docker.env || missing+=("$v")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "⛔ Upgrade blocked: docker.env predates the bundled Garage blob store, and"
    echo "   this compose file cannot start without it:"
    printf '     missing: %s\n' "${missing[@]}"
    echo "   Follow docs/migrate-blob-storage.md, then re-run ./upgrade.sh."
    echo "   Nothing has been changed."
    exit 1
fi

echo "Downloading and building new images..."
docker compose build

echo "Bringing up new containers to replace existing ones..."
docker compose up -d

echo "Removing unused images..."
docker image prune -a -f
