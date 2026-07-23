#!/bin/bash
# ============================================================
# deploy-persona-db-compose.sh
# Deploy Hermes + Persona DB API via docker-compose
#
# 相較 deploy-persona-db-api.sh，改用 docker-compose 管理：
#   - 改 .env 後只要 docker compose up -d，不用 rm + run
#   - 一個 yaml 同時管理 hermes + persona-db-api 兩個 container
#   - 需要 docker-compose-plugin（apt install docker-compose-plugin）
#
# Usage: bash deploy-persona-db-compose.sh
# ============================================================

set -e

# Hermes image — override with HERMES_IMAGE env var, default to local registry
HERMES_IMAGE="${HERMES_IMAGE:-192.168.1.178:31631/hermes-agent:latest}"
# Dynamic UID/GID — matches ubuntu user on this VM (not hardcoded 1000)
HERMES_UID="${HERMES_UID:-$(id -u ubuntu)}"
HERMES_GID="${HERMES_GID:-$(id -g ubuntu)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL="$SCRIPT_DIR/persona-db-rel-1.0.tar.gz"
DEST_DIR="/tmp/persona-db-rel-1.0"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
API_PORT="${API_PORT:-8000}"

# ─── Prerequisites ───
command -v docker >/dev/null || { echo "❌ docker not found"; exit 1; }

# Detect compose command: plugin (docker compose) or standalone (docker-compose)
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "⚠️  Neither 'docker compose' nor 'docker-compose' found."
  echo "   Install one of:"
  echo "     sudo apt install -y docker-compose-v2          # Ubuntu repo"
  echo "     sudo pip install docker-compose                 # pip"
  echo "     sudo curl -L https://github.com/docker/compose/releases/...  # binary"
  exit 1
fi
echo "  ✅ Compose: $COMPOSE_CMD"

[ -f "$TARBALL" ] || { echo "❌ Tarball not found: $TARBALL"; exit 1; }
[ -f "$COMPOSE_FILE" ] || { echo "❌ docker-compose.yml not found next to script"; exit 1; }

echo "============================================"
echo " Hermes + Persona DB API — docker-compose"
echo " Target: $(hostname) | $(date)"
echo "============================================"

# ─── Step 1: Extract tarball ───
echo ""
echo "【1/6】Extracting persona-db tarball..."
rm -rf "$DEST_DIR"
tar xzf "$TARBALL" -C /tmp
echo "  ✅ Extracted"

# ─── Step 2: Create .env (if not exists) ───
echo ""
echo "【2/6】Creating .env..."
if [ ! -f /home/ubuntu/.env ]; then
  cat > /home/ubuntu/.env << 'ENVEOF'
# Persona DB API Configuration
# LLM_API_KEY not required — API works standalone with keyword filtering.
# LLM_API_KEY=your-de...key
# LLM_MODEL=deepseek-chat
# LLM_BASE_URL=https://api.deepseek.com
ENVEOF
  echo "  ✅ .env created (edit to add LLM_API_KEY for LLM features)"
else
  echo "  ⏭️ .env already exists"
fi

# ─── Step 3: Build persona-db-api image ───
echo ""
echo "【3/6】Building persona-db-api image..."
cd "$DEST_DIR"
docker build -t persona-db-api:latest .
echo "  ✅ Image built"

# ─── Step 4: Pull Hermes image ───
echo ""
echo "【4/6】Pulling Hermes image..."
docker pull "$HERMES_IMAGE"
echo "  ✅ Hermes image ready ($HERMES_IMAGE)"

# ─── Step 5: Ensure .hermes directory ───
echo ""
echo "【5/6】Ensuring ~/.hermes directory..."
sudo mkdir -p /home/ubuntu/.hermes/skills /home/ubuntu/.hermes/persona /home/ubuntu/.hermes/persona-tools
sudo chown ubuntu:ubuntu /home/ubuntu/.hermes 2>/dev/null || true
echo "  ✅ Directory ready"

# ─── Step 6: Start via docker-compose ───
echo ""
echo "【6/6】Starting containers via $COMPOSE_CMD..."
cd "$SCRIPT_DIR"
HERMES_UID="$HERMES_UID" HERMES_GID="$HERMES_GID" $COMPOSE_CMD -f "$COMPOSE_FILE" up -d 2>&1
echo "  ✅ Containers started"

# ─── Verify ───
echo ""
echo "--- Verify ---"
sleep 3
docker ps --filter name=hermes --format "  hermes:       {{.Status}}"
docker ps --filter name=persona-db-api --format "  persona-db-api: {{.Status}}"

HEALTH=$(curl -s http://localhost:${API_PORT}/health 2>/dev/null)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
  echo "  API health:    ✅ ok"
  echo "  Personas:      $(echo $HEALTH | python3 -c "import sys,json; print(json.load(sys.stdin).get('persona_count','?'))" 2>/dev/null)"
else
  echo "  ⚠️  API health check failed"
fi

echo ""
echo "============================================"
echo " ✅ Deployment Complete!"
echo ""
echo "  Manage:  docker compose -f $COMPOSE_FILE [up -d|down|logs|ps]"
echo "  Update .env → docker compose up -d (no rm needed)"
echo "============================================"
