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
#   bash deploy-persona-db-compose.sh              # Full deploy (hermes + api)
#   bash deploy-persona-db-compose.sh --skip-hermes # API only (no hermes container)
#
# Environment variables:
#   PERSONA_DB_DATA  — shared data directory (default: /srv/persona-db-data)
#   HERMES_HOME      — Hermes config directory (default: /home/ubuntu/.hermes)
#   API_PORT         — API port (default: 8000)
#   SUDO_PASSWORD    — set this if sudo needs a password (avoid interactive prompt)
# ============================================================

set -e

# ── Parse flags ──────────────────────────────────────────
SKIP_HERMES=false
for arg in "$@"; do
  case "$arg" in
    --skip-hermes) SKIP_HERMES=true ;;
    --help|-h)
      echo "Usage: bash deploy-persona-db-compose.sh [--skip-hermes]"
      echo ""
      echo "  --skip-hermes    Deploy API only, skip Hermes container (~3.8GB pull)"
      exit 0
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PERSONA_DB_DATA="${PERSONA_DB_DATA:-/srv/persona-db-data}"
HERMES_HOME="${HERMES_HOME:-/home/ubuntu/.hermes}"
API_PORT="${API_PORT:-8000}"
TARBALL="${SCRIPT_DIR}/persona-db-rel-1.0.tar.gz"

# ── Helper: sudo with optional password ─────────────────
SUDO_CMD="sudo"
if [ -n "$SUDO_PASSWORD" ]; then
  SUDO_CMD="echo '$SUDO_PASSWORD' | sudo -S"
fi

_cmd() {
  # Run a command, using sudo prefix if needed
  if [[ "$1" == "sudo "* ]]; then
    if [ -n "$SUDO_PASSWORD" ]; then
      echo "$SUDO_PASSWORD" | sudo -S ${@:2} 2>/dev/null
    else
      sudo ${@:2}
    fi
  else
    "$@"
  fi
}

_try_sudo() {
  # Try a sudo command; if password is needed and not provided, skip with warning
  local desc="$1"; shift
  if [ -n "$SUDO_PASSWORD" ]; then
    echo "$SUDO_PASSWORD" | sudo -S "$@" 2>/dev/null && return 0
    echo "  ⚠️  ${desc} failed — run manually or set SUDO_PASSWORD"
    return 1
  fi
  # Try passwordless sudo first
  if sudo -n true 2>/dev/null; then
    sudo "$@" && return 0
  fi
  # Still try — may prompt but we note it
  if sudo "$@" 2>/dev/null; then
    return 0
  fi
  echo "  ⚠️  ${desc} failed — run manually or set SUDO_PASSWORD"
  return 1
}

# ── Pre-flight checks ───────────────────────────────────
echo "============================================"
echo " Persona DB — Compose Deploy"
echo "============================================"
echo ""
echo "  Shared data:  ${PERSONA_DB_DATA}"
echo "  Hermes home:  ${HERMES_HOME}"
echo "  API port:     ${API_PORT}"
echo "  Skip Hermes:  ${SKIP_HERMES}"
echo ""

echo "【0/5】Pre-flight checks..."

# 0a. Docker
command -v docker >/dev/null || { echo "  ❌ docker not found. Install: sudo apt install docker.io"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "  ❌ docker compose plugin not found"; exit 1; }
echo "  ✅ $(docker --version)"
echo "  ✅ $(docker compose version)"

# 0b. Docker socket / group — warn if we can't run docker
if ! docker info >/dev/null 2>&1; then
  echo "  ⚠️  Cannot access Docker socket. Try: sudo usermod -aG docker $(whoami) && newgrp docker"
  echo "     Or set SUDO_PASSWORD in environment for sudo-based docker."
fi

# 0c. Sudo capability
if sudo -n true 2>/dev/null; then
  echo "  ✅ Passwordless sudo available"
elif [ -n "$SUDO_PASSWORD" ]; then
  echo "  ✅ SUDO_PASSWORD set (will use silent sudo)"
else
  echo "  ⚠️  Sudo needs a password. If mkdir/chown steps fail, re-run with:"
  echo "     export SUDO_PASSWORD=your_sudo_password"
  echo "     or pre-create directories manually (see README Troubleshooting)."
fi

# 0d. Disk space (need at least 3GB free for full deploy, 1GB for API-only)
MIN_SPACE=$([ "$SKIP_HERMES" = true ] && echo "1" || echo "3")
AVAIL_GB=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
if [ "$AVAIL_GB" -lt "$MIN_SPACE" ]; then
  echo "  ❌ Only ${AVAIL_GB}GB available, need ${MIN_SPACE}GB. Free up space first:"
  echo "     sudo docker system prune -af"
  echo "     sudo apt-get clean"
  echo "     sudo journalctl --vacuum-time=1d"
  exit 1
fi
echo "  ✅ Disk space: ${AVAIL_GB}GB available"

# 0e. Docker Hub reachability (skip if --skip-hermes)
if [ "$SKIP_HERMES" = false ]; then
  if curl -sI --connect-timeout 10 https://registry-1.docker.io/v2/ >/dev/null 2>&1; then
    echo "  ✅ Docker Hub reachable"
  else
    echo "  ⚠️  Docker Hub unreachable. If pull fails, re-run with --skip-hermes"
  fi
fi

# ── Step 1: Prepare Hermes home ─────────────────────────
echo ""
echo "【1/5】Preparing Hermes config directory..."

# Create required subdirectories — try with sudo, fall back to mkdir
SUBDIRS="cron sessions memories skills persona persona-tools logs shared cache audio_cache image_cache hooks pairing lazy-packages"
for d in $SUBDIRS; do
  mkdir -p "${HERMES_HOME}/${d}" 2>/dev/null || true
done

# Try to set ownership (needs sudo, not critical for functionality)
if sudo -n true 2>/dev/null; then
  sudo chown -R "$(whoami)" "${HERMES_HOME}" 2>/dev/null || true
elif [ -n "$SUDO_PASSWORD" ]; then
  echo "$SUDO_PASSWORD" | sudo -S chown -R "$(whoami)" "${HERMES_HOME}" 2>/dev/null || true
fi

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

echo "  ✅ Hermes home ready"

# ── Step 2: Extract tarball to shared directory ─────────
echo ""
echo "【2/5】Setting up shared data directory..."
if [ ! -f "${PERSONA_DB_DATA}/tw_persona_1069.json" ]; then
  if [ -f "$TARBALL" ]; then
    mkdir -p "${PERSONA_DB_DATA}" 2>/dev/null || true
    tar xzf "$TARBALL" -C "${PERSONA_DB_DATA}" --strip-components=1
    if [ -f "${PERSONA_DB_DATA}/tw_persona_1069.json" ]; then
      echo "  ✅ Extracted tarball to ${PERSONA_DB_DATA}"
    else
      # Maybe extraction needs sudo (tarball was root-owned)
      _try_sudo "tarball extraction" tar xzf "$TARBALL" -C "${PERSONA_DB_DATA}" --strip-components=1
    fi
  else
    echo "  ❌ Tarball not found: ${TARBALL}"
    echo "     Also no existing data at ${PERSONA_DB_DATA}"
    exit 1
  fi
else
  echo "  ✅ Data already present at ${PERSONA_DB_DATA}"
fi

# Set ownership on shared data dir if possible
_try_sudo "chown shared data" chown -R "$(whoami)" "${PERSONA_DB_DATA}" 2>/dev/null || true

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

# ── Step 3: Inject persona-db skills ────────────────────
echo ""
echo "【3/5】Injecting persona-db skills..."
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

# ── Step 4: Build & start containers ────────────────────
echo ""
echo "【4/5】Building & starting containers..."

cd "$SCRIPT_DIR"

# Build api image (always, from local Dockerfile — no network needed for base image if cached)
echo "  🏗️  Building persona-db-api image..."
docker build -t persona-db-api:latest "${PERSONA_DB_DATA}" 2>&1 | tail -3 || {
  echo "  ⚠️  Docker build failed, trying with sudo..."
  if sudo -n true 2>/dev/null; then
    sudo docker build -t persona-db-api:latest "${PERSONA_DB_DATA}" 2>&1 | tail -3
  elif [ -n "$SUDO_PASSWORD" ]; then
    echo "$SUDO_PASSWORD" | sudo -S docker build -t persona-db-api:latest "${PERSONA_DB_DATA}" 2>&1 | tail -3
  else
    echo "  ❌ Build failed. Ensure docker is accessible (docker group or sudo)."
    exit 1
  fi
}
echo "  ✅ persona-db-api image built"

# Pull hermes image (only if not skipped)
if [ "$SKIP_HERMES" = false ]; then
  echo "  📥 Pulling nousresearch/hermes-agent:latest (this may take a while)..."
  docker pull nousresearch/hermes-agent:latest 2>&1 | tail -5 || {
    echo "  ⚠️  Hermes pull failed. Continuing with API-only mode."
    echo "     Re-run with --skip-hermes to avoid this check."
    SKIP_HERMES=true
  }
fi

# Start the API container directly (simpler than docker-compose when hermes is skipped)
echo "  🚀 Starting persona-db-api container..."
# Remove old container if exists
docker rm -f persona-db-api 2>/dev/null || true
docker rm -f hermes 2>/dev/null || true

docker run -d \
  --name persona-db-api \
  -p ${API_PORT}:8000 \
  -v "${PERSONA_DB_DATA}:/app" \
  -v "${HERMES_HOME}:/hermes-config:ro" \
  persona-db-api:latest

echo "  ✅ persona-db-api container started"

# Start hermes container (only if not skipped)
if [ "$SKIP_HERMES" = false ]; then
  docker run -d \
    --name hermes \
    --network host \
    --restart unless-stopped \
    -v "${HERMES_HOME}:/opt/data" \
    -v "${PERSONA_DB_DATA}:/root/persona-db" \
    nousresearch/hermes-agent:latest \
    /bin/sh -c "sleep infinity"
  echo "  ✅ Hermes container started"
fi

# ── Step 5: Verify ──────────────────────────────────────
echo ""
echo "【5/5】Verifying..."
sleep 5

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
curl -s http://localhost:${API_PORT}/personadb/status 2>/dev/null | grep -E "Version|Backup|QA|Git|LLM" || echo "  (status not ready)"

if [ "$SKIP_HERMES" = false ]; then
  echo ""
  echo "=== Hermes ==="
  docker exec hermes hermes --version 2>/dev/null | head -1 || echo "  (hermes may still be starting)"
  echo "  Skills: $(docker exec hermes find /opt/data/skills -name SKILL.md 2>/dev/null | wc -l) SKILL.md files"

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
fi

echo ""
echo "============================================"
echo " ✅ Deploy Complete!"
echo ""
if [ "$SKIP_HERMES" = true ]; then
echo "    Mode: API only (hermes container skipped)"
echo "    To add hermes later:"
echo "      docker pull nousresearch/hermes-agent:latest"
echo "      docker run -d --name hermes --network host ..."
else
echo "    Hermes CLI: docker exec -it hermes hermes chat"
fi
echo "    API status: curl http://localhost:${API_PORT}/personadb/status"
echo "    Test:       bash ${SCRIPT_DIR}/test-persona-db-api.sh"
echo "    Logs:       docker logs persona-db-api -f"
echo "    Down:       docker rm -f persona-db-api hermes"
echo "============================================"
