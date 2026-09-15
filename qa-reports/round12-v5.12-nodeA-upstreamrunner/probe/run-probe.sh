#!/bin/bash
# round12 §6.8 重現性探針 + §6.9 定向探針（v5.12 / NODE-A）
#
# 必須在主套件「跑完之後」才執行 —— 併跑會互相影響延遲量測。
# OUT 自我定位：probe/ 的上一層就是本輪目錄（不寫死輪次，複製到哪一輪都對）
#
# ⚠️ 探針題目原文（skill v2.4.0 規定：原文必須寫進報告/README，不可只寫「窄查詢」）
#   t1/t2 用的是**刻意設計為「超出 schema、必然不可滿足」**的查詢：
#       questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主
#   Persona DB 的 24 個欄位沒有「遊艇」也沒有「私人飛機」，所以它必然逼出
#   matched=0 / pool_exhausted=true（主套件碰不到的分支）。
#   **它是探針，不是業務案例，也不是產品缺陷主張。**（同一題自第九輪起重複作為回歸哨兵）

BASE_URL="${BASE_URL:-http://localhost:8000}"
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)}"
P="$OUT/probe"
mkdir -p "$P"
exec > >(tee -a "$P/probe.log") 2>&1
echo "# probe start $(date -u +%Y-%m-%dT%H:%M:%SZ)  BASE_URL=$BASE_URL  host=$(hostname)  OUT=$OUT"

probe() {   # probe <id> <label> <curl args...>
  local id="$1" label="$2"
  shift 2
  echo ""
  echo "=== ${label} ==="
  time curl -s --get "${BASE_URL}/personadb/candidates" "$@" \
    -D "$P/${id}.headers" -o "$P/${id}.body" \
    -w 'http_code=%{http_code}\ntime_total=%{time_total}\nsize_download=%{size_download}\nurl_effective=%{url_effective}\n' > "$P/${id}.w"
  {
    echo "# probe = ${id}"
    echo "# label = ${label}"
    echo "# cmd   = curl -s --get ${BASE_URL}/personadb/candidates $*"
    cat "$P/${id}.w"
  } > "$P/${id}.meta"
  echo "  → $(tr '\n' ' ' < "$P/${id}.w")"
}

# ── §6.8 重現性探針 ──────────────────────────────────────────────────
# case08（小吃攤老闆的目標客群 = 顧客語意）：第十一輪量到**雙峰**（4 次中 2 次把顧客
#   誤判成業主本人）。v5.12 新增 #65 主體護欄（subject + 禁用維度剝除）——
#   本輪要看**護欄是否讓它穩定**。
for i in 1 2 3; do
  probe "r08_boss_${i}" "§6.8 重現性 — case08 小吃攤（顧客語意）r${i}/3（#65 主體護欄）" \
    --data-urlencode "questions=小吃攤老闆的目標客群" \
    --data-urlencode "role=夜市商圈協會" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done
# case06（醫美）：第十一輪在這裡出現「值集放寬後又被移除」的跨輪序列，
#   而 v5.12 採納的 #63 S/T 不變式用的是**較嚴的形式** —— 本輪用來檢驗它是否會誤報。
for i in 1 2 3; do
  probe "r06_aesthetic_${i}" "§6.8 重現性 — case06 醫美 r${i}/3（#63 S/T 檢驗）" \
    --data-urlencode "questions=醫美診所的目標客戶" \
    --data-urlencode "role=醫美診所行銷主管" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done

# ── §6.9 定向探針 ────────────────────────────────────────────────────
probe "t1_narrow_topk10" "§6.9 t1 不可滿足查詢 top_k=10（題目原文見檔頭註解）" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
probe "t2_narrow_topk100" "§6.9 t2 同查詢 top_k=100 → pool_exhausted" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=100" \
  --data-urlencode "opMode=僅篩選"
probe "t3_tesla_topk20" "§6.9 t3 TESLA top_k=20 → #61 commute_mode 保護" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=20" \
  --data-urlencode "opMode=僅篩選"
probe "t4_banker_topk20" "§6.9 t4 房貸(銀行) top_k=20 → 值集放寬 / veto" \
  --data-urlencode "questions=房貸優惠方案" \
  --data-urlencode "role=銀行業者" \
  --data-urlencode "top_k=20" \
  --data-urlencode "opMode=僅篩選"

echo ""
echo "# probe end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
touch "$P/PROBE_DONE"   # watcher 等這個檔，不用 pgrep（會 match 自己）
