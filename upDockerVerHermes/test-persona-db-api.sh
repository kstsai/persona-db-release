#!/bin/bash

#echo "LLM_API_KEY=..." >> ~/persona-db/.env
#echo "LLM_MODEL=deepseek-chat" >> ~/persona-db/.env

#docker restart persona-db-api
#sleep 6

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
