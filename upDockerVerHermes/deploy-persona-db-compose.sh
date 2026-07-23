#!/bin/bash
# ============================================================
# deploy-persona-db-compose.sh
# Deploy Hermes + Persona DB API with shared volume via docker compose
#
# Handles EVERYTHING automatically:
#   - Prerequisite directories & permissions
#   - Hermes config with subdirectories (cron, sessions, memories, skills)
#   - Persona-db tarball extraction to shared volume
#   - Skills injection into Hermes config
#   - .env template creation
#   - Container start + verification
#
# Usage:
#   bash deploy-persona-db-compose.sh
#
# Environment variables:
#   PERSONA_DB_DATA  — shared data directory (default: /srv/persona-db-data)
#   HERMES_HOME      — Hermes config directory (default: /home/ubuntu/.hermes)
#   API_PORT         — API port (default: 8000)
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PERSONA_DB_DATA="${PERSONA_DB_DATA:-/srv/persona-db-data}"
HERMES_HOME="${HERMES_HOME:-/home/ubuntu/.hermes}"
API_PORT="${API_PORT:-8000}"
TARBALL="${SCRIPT_DIR}/persona-db-rel-1.0.tar.gz"

echo "============================================"
echo " Persona DB — Compose Deploy"
echo "============================================"
echo ""
echo "  Shared data:  ${PERSONA_DB_DATA}"
echo "  Hermes home:  ${HERMES_HOME}"
echo ""

# ── Step 1: Verify ──────────────────────────────────────
echo "【1/5】Verifying..."
command -v docker >/dev/null || { echo "❌ docker not found"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "❌ docker compose plugin not found"; exit 1; }
echo "  ✅ $(docker --version)"
echo "  ✅ $(docker compose version)"

# ── Step 2: Prepare Hermes home ─────────────────────────
echo ""
echo "【2/5】Preparing Hermes config directory..."
# Create required subdirectories with proper permissions
sudo mkdir -p "${HERMES_HOME}"/{cron,sessions,memories,skills,persona,persona-tools,logs,shared,cache,audio_cache,image_cache,hooks,pairing,lazy-packages}
sudo chown -R "$(whoami)" "${HERMES_HOME}"

# Ensure basic config.yaml exists
if [ ! -f "${HERMES_HOME}/config.yaml" ]; then
  cat > "${HERMES_HOME}/config.yaml" << 'CONFEOF'
agent:
  max_turns: 90
terminal:
  backend: local
delegation:
  max_iterations: 50
memory:
  memory_enabled: true
  user_profile_enabled: true
display:
  interface: tui
CONFEOF
  echo "  ✅ config.yaml created"
else
  echo "  ✅ config.yaml exists"
fi

# Ensure .env exists (Hermes 3.13+ requires it)
if [ ! -f "${HERMES_HOME}/.env" ]; then
  touch "${HERMES_HOME}/.env"
  echo "  ✅ .env created (empty)"
else
  echo "  ✅ .env exists"
fi

# Fix permissions — Hermes container (v3.13) writes to /opt/data/ as root
# but mounted volume may not have the right owner
sudo chmod -R 777 "${HERMES_HOME}" 2>/dev/null || true

sudo chown "$(whoami)" "${HERMES_HOME}/.env" "${HERMES_HOME}/config.yaml" 2>/dev/null || true
echo "  ✅ Hermes home ready"

# ── Step 3: Extract tarball to shared directory ─────────
echo ""
echo "【3/5】Setting up shared data directory..."
if [ ! -f "${PERSONA_DB_DATA}/tw_persona_1069.json" ]; then
  if [ -f "$TARBALL" ]; then
    sudo mkdir -p "${PERSONA_DB_DATA}"
    sudo chown "$(whoami)" "${PERSONA_DB_DATA}"
    tar xzf "$TARBALL" -C "${PERSONA_DB_DATA}" --strip-components=1
    echo "  ✅ Extracted tarball to ${PERSONA_DB_DATA}"
  else
    echo "  ❌ Tarball not found: ${TARBALL}"
    echo "     Also no existing data at ${PERSONA_DB_DATA}"
    exit 1
  fi
else
  echo "  ✅ Data already present at ${PERSONA_DB_DATA}"
fi

# Create .env for persona-db-api
if [ ! -f "${PERSONA_DB_DATA}/.env" ]; then
  cat > "${PERSONA_DB_DATA}/.env" << 'ENVEOF'
# Persona DB API
# LLM_API_KEY=your-deepseek-api-key
# LLM_MODEL=deepseek-chat
# LLM_BASE_URL=https://api.deepseek.com
ENVEOF
  echo "  📄 .env created for persona-db API. Edit to add LLM key:"
  echo "     nano ${PERSONA_DB_DATA}/.env"
else
  echo "  ✅ .env exists for persona-db API"
fi

# ── Step 4: Inject persona-db skills ────────────────────
echo ""
echo "【4/5】Injecting persona-db skills..."
SKILLS_DIR="${HERMES_HOME}/skills"
mkdir -p "${SKILLS_DIR}/research" "${SKILLS_DIR}/productivity" "${SKILLS_DIR}/data-science"

# Copy persona-db skills from tarball into Hermes home
SKILL_SRC="${PERSONA_DB_DATA}/skills"
SKILL_COUNT=0
if [ -d "${SKILL_SRC}/research/tw-persona-db" ]; then
  cp -r "${SKILL_SRC}/research/tw-persona-db" "${SKILLS_DIR}/research/"
  SKILL_COUNT=$((SKILL_COUNT+1))
  echo "  ✅ tw-persona-db skill injected"
fi
if [ -d "${SKILL_SRC}/productivity/persona-db-billing" ]; then
  cp -r "${SKILL_SRC}/productivity/persona-db-billing" "${SKILLS_DIR}/productivity/"
  SKILL_COUNT=$((SKILL_COUNT+1))
  echo "  ✅ persona-db-billing skill injected"
fi
if [ -d "${SKILL_SRC}/data-science/persona-driven-evaluation" ]; then
  cp -r "${SKILL_SRC}/data-science/persona-driven-evaluation" "${SKILLS_DIR}/data-science/"
  SKILL_COUNT=$((SKILL_COUNT+1))
  echo "  ✅ persona-driven-evaluation skill injected"
fi

if [ "$SKILL_COUNT" -eq 0 ]; then
  echo "  ⚠️ No skills found in tarball. Skipping skill injection."
fi

# Also copy persona-tools + JSON data to Hermes home
if [ -d "${PERSONA_DB_DATA}" ]; then
  cp -r "${PERSONA_DB_DATA}"/*.py "${HERMES_HOME}/persona-tools/" 2>/dev/null || true
  cp -r "${PERSONA_DB_DATA}/api/" "${HERMES_HOME}/persona-tools/" 2>/dev/null || true
  if [ -f "${PERSONA_DB_DATA}/tw_persona_1069.json" ]; then
    cp "${PERSONA_DB_DATA}/tw_persona_1069.json" "${HERMES_HOME}/persona/" 2>/dev/null || true
  fi
  echo "  ✅ Persona tools synced to Hermes home"
fi

# ── Step 5: Start containers + verify ───────────────────
echo ""
echo "【5/5】Starting containers..."
docker pull nousresearch/hermes-agent:latest

cd "$SCRIPT_DIR"
PERSONA_DB_DATA="$PERSONA_DB_DATA" \
HERMES_HOME="$HERMES_HOME" \
API_PORT="$API_PORT" \
  docker compose up -d --build

echo "  ✅ Containers started"
echo ""
echo "--- Verifying ---"
sleep 5

echo ""
echo "=== Hermes ==="
docker exec hermes hermes --version 2>/dev/null | head -1 || echo "  (hermes may still be starting)"
echo "  Skills: $(docker exec hermes find /opt/data/skills -name SKILL.md 2>/dev/null | wc -l) SKILL.md files"

echo ""
echo "=== Persona DB API ==="
curl -s http://localhost:${API_PORT}/health 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  Status: {d.get(\"status\")}')
print(f'  DB: {d.get(\"persona_count\")} personas loaded')
" 2>/dev/null || echo "  (API may still be starting)"

echo ""
echo "=== Full Status ==="
curl -s http://localhost:${API_PORT}/personadb/status 2>/dev/null | grep -E "Version|Backup|QA|Git|LLM|Hermes Skills" || echo "  (status not ready)"

echo ""
echo "=== Shared Volume ==="
HERMES_ITEMS=$(docker exec hermes ls /root/persona-db/ 2>/dev/null | wc -l)
API_ITEMS=$(docker exec persona-db-api ls /app/ 2>/dev/null | wc -l)
echo "  Hermes /root/persona-db/: ${HERMES_ITEMS} items"
echo "  API    /app/:            ${API_ITEMS} items"
if [ "$HERMES_ITEMS" -gt 0 ] && [ "$API_ITEMS" -gt 0 ]; then
  echo "  ✅ Shared volume OK — both containers see same data"
else
  echo "  ⚠️ Shared volume issue — check PERSONA_DB_DATA"
fi

echo ""
echo "============================================"
echo " ✅ Deploy Complete!"
echo ""
echo "    Hermes CLI: docker exec -it hermes hermes chat"
echo "    API status: curl http://localhost:${API_PORT}/personadb/status"
echo "    Logs:       cd ${SCRIPT_DIR} && docker compose logs -f"
echo "    Down:       docker compose down"
echo "============================================"
