#!/bin/bash
# Faithful adaptation of kstsai/persona-db-release upDockerVerHermes/test-persona-db-api.sh
# Original targets http://localhost:8000 (runs ON the instance host).
# This variant targets the NODE-A tailscale instance remotely, same endpoints/params/order,
# and additionally persists full evidence (body / headers / curl meta) for human re-verification.
#
# Original script source: https://raw.githubusercontent.com/kstsai/persona-db-release/main/upDockerVerHermes/test-persona-db-api.sh

set -u

BASE_URL="${BASE_URL:-http://NODE-A:8000}"
OUT="${OUT:-/Users/kstsai/Documents/personadb-NODE-A-api-verify}"

mkdir -p "$OUT/raw" "$OUT/json" "$OUT/headers" "$OUT/meta"

# ---- jq guard (parity with original lines 10-13) ----
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq not found — installing..."
  sudo apt-get install -y jq >/dev/null 2>&1 || { echo "❌ jq install failed, case 3 will fail"; }
fi

# helper: case_run <case_id> <label> <url> [curl args...]
case_run() {
  local id="$1"; shift
  local label="$1"; shift
  local url="$1"; shift

  echo ""
  echo "=== ${label} ==="
  echo "--- REQUEST: GET ${url} $* ---"

  # exact request, body to raw/, headers to headers/, timing to meta/
  time curl -s --get "$url" "$@" \
    -D "$OUT/headers/${id}.headers" \
    -o "$OUT/raw/${id}.body" \
    -w '%{http_code}\t%{time_total}\t%{size_download}\t%{url_effective}\n' \
    > "$OUT/meta/${id}.w"

  local wc_code wc_time wc_size wc_url
  wc_code=$(cut -f1 "$OUT/meta/${id}.w")
  wc_time=$(cut -f2 "$OUT/meta/${id}.w")
  wc_size=$(cut -f3 "$OUT/meta/${id}.w")
  wc_url=$(cut -f4 "$OUT/meta/${id}.w")

  {
    echo "case_id: ${id}"
    echo "label: ${label}"
    echo "http_code: ${wc_code}"
    echo "time_total_sec: ${wc_time}"
    echo "size_download_bytes: ${wc_size}"
    echo "url_effective: ${wc_url}"
    echo "curl_args: $*"
  } > "$OUT/meta/${id}.meta"

  echo "--- HTTP ${wc_code} | ${wc_time}s | ${wc_size} bytes ---"
  echo "--- RESPONSE BODY ---"
  cat "$OUT/raw/${id}.body"
  echo ""

  # pretty-print copy if valid JSON, else record the error verbatim
  if jq . "$OUT/raw/${id}.body" > "$OUT/json/${id}.json" 2>"$OUT/meta/${id}.jqerr"; then
    rm -f "$OUT/meta/${id}.jqerr"
    echo "--- (pretty JSON saved: json/${id}.json) ---"
  else
    echo "--- (NOT valid JSON — see meta/${id}.jqerr) ---"
    cat "$OUT/meta/${id}.jqerr"
  fi
}

echo "############################################################"
echo "# persona-db API verification against NODE-A"
echo "# BASE_URL = ${BASE_URL}"
echo "# started  = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# original = kstsai/persona-db-release/upDockerVerHermes/test-persona-db-api.sh"
echo "############################################################"

# ---- 0. status (original line 17) ----
case_run "00_status" "0. /personadb/status" "${BASE_URL}/personadb/status"

# ---- 1 (original lines 19-24) ----
case_run "01_kangshimei" "1. 康是美的目標客戶" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=康是美的目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"

# ---- 2 (original lines 27-31) ----
case_run "02_tesla" "2. TESLA的目標客戶" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"

# ---- 3 (original lines 34-38) ----
case_run "03_fashion" "3. 時尚服裝設計師的目標客戶" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=時尚服裝設計師的目標客戶" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# ---- 4 (original lines 42-47) ----
case_run "04_role_fangzhong" "4. 房貸優惠 — 房仲業者" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=房貸優惠方案" \
  --data-urlencode "role=房仲業者" \
  --data-urlencode "top_k=5" \
  --data-urlencode "opMode=僅篩選"

# ---- 5 (original lines 50-55) ----
case_run "05_role_banker" "5. 房貸優惠 — 銀行業者" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=房貸優惠方案" \
  --data-urlencode "role=銀行業者" \
  --data-urlencode "top_k=5" \
  --data-urlencode "opMode=僅篩選"

# ---- 6 (original lines 58-63) ----
case_run "06_aesthetic" "6. 醫美診所的目標客戶（dimension 20: aesthetic_procedure）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=醫美診所的目標客戶" \
  --data-urlencode "role=醫美診所行銷主管" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# ---- 7 (original lines 66-71) ----
case_run "07_debt" "7. 債務整合的目標客戶（dimension 21: debt_status）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=債務整合貸款方案的目標客戶" \
  --data-urlencode "role=銀行債務整合專員" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# ---- 8 (original lines 74-79) ----
case_run "08_boss" "8. 小吃攤老闆的目標客群（dimension 22: employment_status）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=小吃攤老闆的目標客群" \
  --data-urlencode "role=夜市商圈協會" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# ---- Role QA: diff check (original lines 82-90) ----
echo ""
echo "=== Role QA: diff check ==="
FZ_TOP=$(jq -r '.persona_ids[0]' "$OUT/json/04_role_fangzhong.json" 2>/dev/null || echo "ERROR")
BK_TOP=$(jq -r '.persona_ids[0]' "$OUT/json/05_role_banker.json" 2>/dev/null || echo "ERROR")
echo "  房仲 top=$FZ_TOP, 銀行 top=$BK_TOP"
if [ "$FZ_TOP" != "$BK_TOP" ]; then
  echo "  ✅ DIFFERENT — role is working"
else
  echo "  ⚠️  SAME — role may not be differentiating on this query"
fi

echo ""
echo "# finished = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
