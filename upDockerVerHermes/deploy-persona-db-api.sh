#!/bin/bash
# ============================================================
# deploy-persona-db-api.sh
# Deploy Persona DB API to a Linux host with Docker
#
# Uses pre-packaged persona-db-rel-1.0.tar.gz (no git needed).
# No external model dependency — API works standalone with
# keyword filtering. LLM features optional.
#
# Usage:
#   # Place persona-db-rel-1.0.tar.gz next to this script
#   bash deploy-persona-db-api.sh
#
#   # Or specify custom tarball path
#   bash deploy-persona-db-api.sh /path/to/persona-db-rel-1.0.tar.gz
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL="${1:-$SCRIPT_DIR/persona-db-rel-1.0.tar.gz}"
EXTRACT_DIR="/tmp/persona-db-rel-1.0"
API_PORT="${API_PORT:-8000}"

echo "============================================"
echo " Persona DB API — Deployment Script"
echo " Target: $(hostname) | $(uname -a)"
echo " Date:   $(date)"
echo "============================================"

# Validate tarball
if [ ! -f "$TARBALL" ]; then
  echo "❌ Tarball not found: $TARBALL"
  echo "   Generate it first: bash pack-persona-db-release.sh"
  echo "   Or download from release bundle."
  exit 1
fi

# Step 1: Verify Docker
echo ""
echo "【1/5】Verifying prerequisites..."
command -v docker >/dev/null || { echo "❌ docker not found"; exit 1; }
echo "  ✅ docker: $(docker --version | head -1)"

# Step 2: Extract tarball
echo ""
echo "【2/5】Extracting persona-db release..."
rm -rf "$EXTRACT_DIR"
tar xzf "$TARBALL" -C /tmp
echo "  ✅ Extracted to $EXTRACT_DIR"
echo "  ✅ Contents: $(find "$EXTRACT_DIR" -name '*.py' | wc -l) Python files"
cd "$EXTRACT_DIR"

# Step 3: Create .env (no external model required)
echo ""
echo "【3/5】Creating .env configuration..."
if [ ! -f .env ]; then
  cat > .env << 'ENVEOF'
# Persona DB API Configuration
# LLM_API_KEY not required — API works standalone with keyword filtering.
# Set these only if you want LLM-powered question analysis + simulation:
# LLM_API_KEY=your-deepseek-api-key
# LLM_MODEL=deepseek-chat
# LLM_BASE_URL=https://api.deepseek.com
ENVEOF
  echo "  ✅ .env created. No API key needed for basic operation."
  echo "  💡 To enable LLM features, set LLM_API_KEY in: $EXTRACT_DIR/.env"
else
  echo "  ⏭️ .env already exists"
fi

# Step 4: Build Docker image
echo ""
echo "【4/5】Building Docker image..."
docker build -t persona-db-api:latest .
echo "  ✅ Image built"

# Step 5: Run container
echo ""
echo "【5/5】Starting container..."
docker stop persona-db-api 2>/dev/null || true
docker rm persona-db-api 2>/dev/null || true

docker run -d \
  --name persona-db-api \
  -p "${API_PORT}:8000" \
  --env-file .env \
  -v /home/ubuntu/.hermes:/hermes-config:ro \
  --restart unless-stopped \
  persona-db-api:latest

echo "  ✅ Container started on port ${API_PORT}"

# Verify
echo ""
echo "--- Verifying API ---"
sleep 3
HEALTH=$(curl -s http://localhost:${API_PORT}/health 2>/dev/null)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
  echo "  ✅ Health check passed"
  echo "  📊 Persona DB: $(echo $HEALTH | python3 -c "import sys,json; print(json.load(sys.stdin).get('persona_count','?'))" 2>/dev/null) personas loaded"
else
  echo "  ⚠️ Health check failed. Check: docker logs persona-db-api"
fi

echo ""
echo "============================================"
echo " ✅ Deployment Complete!"
echo ""
echo "    API:          http://localhost:${API_PORT}"
echo "    Docs:         http://localhost:${API_PORT}/docs"
echo "    Tarball:      ${TARBALL}"
echo ""
echo "    Examples:"
echo "      curl 'http://localhost:${API_PORT}/personadb/candidates?questions=台北市35-44科技業&top_k=3&opMode=僅篩選'"
echo "      curl 'http://localhost:${API_PORT}/personadb/detail?persona_id=1'"
echo ""
echo "    With LLM key set:"
echo "      curl 'http://localhost:${API_PORT}/personadb/candidates?questions=康是美的目標客戶&top_k=3&opMode=篩選+模擬'"
echo "============================================"
