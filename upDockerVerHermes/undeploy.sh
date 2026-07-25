#!/bin/bash
# Undeploy: stop containers + clean data
set -e
cd "$(dirname "$0")"
docker stop hermes 2>/dev/null || true
docker rm hermes 2>/dev/null || true
docker stop persona-db-api 2>/dev/null || true
docker rm persona-db-api 2>/dev/null || true
sudo rm -rf /srv/persona-db-data/
sudo rm -rf ~/.hermes/
echo "✅ Undeploy complete"

