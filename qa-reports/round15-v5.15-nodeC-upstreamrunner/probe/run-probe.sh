#!/bin/bash
# round14 §6.8 重現性探針 + §6.9 定向探針（v5.14 / NODE-A）
#
# 必須在主套件「跑完之後」才執行 —— 併跑會互相影響延遲量測。
# OUT 自我定位：probe/ 的上一層就是本輪目錄（不寫死輪次，複製到哪一輪都對）
#
# ⚠️ 探針題目原文（skill v2.4.0 規定：原文必須寫進報告/README，不可只寫「窄查詢」）
#
#   t1  不可滿足查詢（自第九輪起的回歸哨兵）：
#       questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主
#       Persona DB 的 24 個欄位沒有「遊艇」／「私人飛機」⇒ 必然逼出 matched=0 / pool_exhausted=true。
#
#   t2  過衝探針（本輪新增，為了逼出 v5.14 的 #70 A `overshoot_restore`）：
#       questions=時尚服裝設計師的目標客戶   role 不帶   top_k=10（= 主套件 case03 的完全相同參數）
#       為什麼用這一題：第十三輪的 case03 正是在這裡發生 overshoot（移除 hobby 使 18→105 = 5.8×）。
#       #70 A 的邏輯是「某一輪放寬後樣本數 > 2×TARGET_MIN(40) ⇒ 還原該輪、把被移除的維度併入保護集」，
#       所以需要一題「會把樣本數衝過 40」的查詢。用主套件案例的原參數可降低額外變因。
#
#   t3  收窄醫美（第十三輪新增的 #66 C 探針）：
#       questions=想找做過醫美療程的45歲單身女性
#       收窄到讓「已套用維度 ⊆ 保護集」成立 ⇒ 逼出 protection_saturated。
#
#   t4  TESLA top_k=20（#61 commute_mode 保護的回歸）
#
#   ⚠️ t1/t2/t3 都是**刻意設計**的探針，不是業務案例，也不是產品缺陷主張。
#      人造查詢驗的是**分支機制**，不是真實流量。

BASE_URL="${BASE_URL:-http://[ts-peer-ip]:8000}"
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
for i in 1 2 3; do
  probe "r08_boss_${i}" "§6.8 重現性 — case08 小吃攤（顧客語意）r${i}/3（#65 主體護欄）" \
    --data-urlencode "questions=小吃攤老闆的目標客群" \
    --data-urlencode "role=夜市商圈協會" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done
for i in 1 2 3; do
  probe "r06_aesthetic_${i}" "§6.8 重現性 — case06 醫美 r${i}/3（保護集／值集放寬幅度 #69）" \
    --data-urlencode "questions=醫美診所的目標客戶" \
    --data-urlencode "role=醫美診所行銷主管" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done

# ── §6.9 定向探針 ────────────────────────────────────────────────────
probe "t1_narrow_topk10" "§6.9 t1 不可滿足查詢 top_k=10（題目原文見檔頭）" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
probe "t2_fashion_overshoot" "§6.9 t2 時尚（case03 原參數）→ 逼出 overshoot_restore（#70 A）" \
  --data-urlencode "questions=時尚服裝設計師的目標客戶" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
probe "t3_aesthetic_narrow" "§6.9 t3 收窄醫美 → protection_saturated（#66 C 回歸）" \
  --data-urlencode "questions=想找做過醫美療程的45歲單身女性" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
probe "t4_tesla_topk20" "§6.9 t4 TESLA top_k=20 → #61 commute_mode 保護" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=20" \
  --data-urlencode "opMode=僅篩選"

echo ""
echo "# probe end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
touch "$P/PROBE_DONE"   # watcher 等這個檔，不用 pgrep（會 match 自己）
