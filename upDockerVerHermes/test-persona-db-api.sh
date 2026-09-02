#!/bin/bash

# echo "LLM_API_KEY=..." >> ~/persona-db/.env
# echo "LLM_MODEL=deepseek-chat" >> ~/persona-db/.env

# docker restart persona-db-api
# sleep 6

# jq 必要（case 3 用）— 缺則自動安裝
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq not found — installing..."
  sudo apt-get install -y jq >/dev/null 2>&1 || { echo "❌ jq install failed, case 3 will fail"; }
fi

# 正確版 ✅ — 中文自動 URL encode

time curl --get "http://localhost:8000/personadb/status"

echo ""
echo "=== 1. 康是美的目標客戶 ==="
time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=康是美的目標客戶" \
            --data-urlencode "top_k=3" \
              --data-urlencode "opMode=僅篩選"

echo ""
echo "=== 2. TESLA的目標客戶 ==="
time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=TESLA的目標客戶" \
            --data-urlencode "top_k=3" \
              --data-urlencode "opMode=僅篩選"

echo ""
echo "=== 3. 時尚服裝設計師的目標客戶 ==="
time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=時尚服裝設計師的目標客戶" \
            --data-urlencode "top_k=10" \
              --data-urlencode "opMode=僅篩選" | jq > fashion_closing.json


echo ""
echo "=== 4. 房貸優惠 — 房仲業者 ==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=房貸優惠方案" \
          --data-urlencode "role=房仲業者" \
          --data-urlencode "top_k=5" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/role_fangzhong.json

echo ""
echo "=== 5. 房貸優惠 — 銀行業者 ==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=房貸優惠方案" \
          --data-urlencode "role=銀行業者" \
          --data-urlencode "top_k=5" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/role_banker.json

echo ""
echo "=== 6. 醫美診所的目標客戶（dimension 20: aesthetic_procedure）==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=醫美診所的目標客戶" \
          --data-urlencode "role=醫美診所行銷主管" \
          --data-urlencode "top_k=10" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/aesthetic_closing.json

echo ""
echo "=== Role QA: diff check ==="
FZ_TOP=$(python3 -c "import json; d=json.load(open('/tmp/role_fangzhong.json')); print(d['persona_ids'][0])" 2>/dev/null || echo "ERROR")
BK_TOP=$(python3 -c "import json; d=json.load(open('/tmp/role_banker.json')); print(d['persona_ids'][0])" 2>/dev/null || echo "ERROR")
echo "  房仲 top=$FZ_TOP, 銀行 top=$BK_TOP"
if [ "$FZ_TOP" != "$BK_TOP" ]; then
  echo "  ✅ DIFFERENT — role is working"
else
  echo "  ⚠️  SAME — role may not be differentiating on this query"
fi
