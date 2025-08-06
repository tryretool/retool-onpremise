#!/bin/bash

echo "Downloading and building new images..."
docker compose build

echo "Bringing up new containers to replace existing ones..."
docker compose up -d

echo "Removing unused images..."
docker image prune -a -f
