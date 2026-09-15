#!/bin/bash
# round11 §6.8 重現性探針 + §6.9 定向探針（v5.11.1 / NODE-A）
# 必須在主套件「跑完之後」才執行 —— 併跑會互相影響延遲量測。
# 證據獨立落盤到 probe/，並在報告標明「主套件未涵蓋此分支」。

BASE_URL="${BASE_URL:-http://localhost:8000}"
# OUT 自我定位：probe/ 的上一層就是本輪目錄（不寫死輪次，複製到哪一輪都對）
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

# ── §6.8 重現性探針（各 3 次）────────────────────────────────────────
# case06 醫美：v5.10 那一輪曾在這裡出現「值集放寬（sex 女→女+男）」，本輪要看 #63 的
#              widened_dims 是否真的留下痕跡。
# case07 債務整合：v5.10 那一輪曾在重跑時落入空池（matched=0）並出現**空值清單**，
#              本輪要看 #62 的空清單正規化是否生效、以及 #58 status 語意。
for i in 1 2 3; do
  probe "r06_aesthetic_${i}" "§6.8 重現性 — case06 醫美 r${i}/3（#63 值集放寬留痕）" \
    --data-urlencode "questions=醫美診所的目標客戶" \
    --data-urlencode "role=醫美診所行銷主管" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done
for i in 1 2 3; do
  probe "r07_debt_${i}" "§6.8 重現性 — case07 債務整合 r${i}/3（#62 空清單／#58 status）" \
    --data-urlencode "questions=債務整合貸款方案的目標客戶" \
    --data-urlencode "role=銀行債務整合專員" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done

# ── §6.9 定向探針 ────────────────────────────────────────────────────
# t1：極窄查詢 → v5.10 那一輪正是這一題產出**空值清單**（age: []、family_income: []）
#     ⇒ 驗 #62：applied_filters 不得再出現空值清單（且空維度應被「丟棄」而非留空）
probe "t1_narrow_topk10" "§6.9 t1 極窄查詢 top_k=10 → #62 空值清單正規化" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
# t2：同查詢 + top_k=100 → pool_exhausted=true 分支 + #58 status
probe "t2_narrow_topk100" "§6.9 t2 窄查詢 top_k=100 → pool_exhausted / status" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=100" \
  --data-urlencode "opMode=僅篩選"
# t3：TESLA + 較大 top_k → 逼放寬迴圈去動 commute_mode（#61 的保護維度）
probe "t3_tesla_topk20" "§6.9 t3 TESLA top_k=20 → protected_veto / #61 保護" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=20" \
  --data-urlencode "opMode=僅篩選"
# t4：房貸（銀行業者）+ 較大 top_k → 誘發「值集放寬」（v5.10 在這一題放寬過 income/family_income）
probe "t4_banker_topk20" "§6.9 t4 房貸(銀行) top_k=20 → #63 widened_dims 留痕" \
  --data-urlencode "questions=房貸優惠方案" \
  --data-urlencode "role=銀行業者" \
  --data-urlencode "top_k=20" \
  --data-urlencode "opMode=僅篩選"

echo ""
echo "# probe end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
touch "$P/PROBE_DONE"   # watcher 等這個檔，不用 pgrep（會 match 自己）
