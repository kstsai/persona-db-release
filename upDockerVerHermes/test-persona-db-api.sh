#!/bin/bash

#echo "LLM_API_KEY=sk-b9b97c0f4bb545d4a3ef8ad6a27ed980" >> ~/persona-db/.env
#echo "LLM_MODEL=deepseek-chat" >> ~/persona-db/.env

#docker restart persona-db-api
#sleep 6

# 正確版 ✅ — 中文自動 URL encode

time curl --get "http://localhost:8000/personadb/status"

time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=康是美的目標客戶" \
            --data-urlencode "top_k=3" \
              --data-urlencode "opMode=僅篩選"

time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=TESLA的目標客戶" \
            --data-urlencode "top_k=3" \
              --data-urlencode "opMode=僅篩選"
