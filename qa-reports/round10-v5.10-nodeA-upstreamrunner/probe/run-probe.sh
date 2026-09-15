#!/bin/bash
# round10 §6.8 重現性探針 + §6.9 定向探針（v5.10 / NODE-A）
# 必須在主套件「跑完之後」才執行 —— 併跑會互相影響延遲量測。
# 證據獨立落盤到 probe/，並在報告標明「主套件未涵蓋此分支」。

BASE_URL="${BASE_URL:-http://localhost:8000}"
OUT="${OUT:-$HOME/qa-round10}"
P="$OUT/probe"
mkdir -p "$P"
exec > >(tee -a "$P/probe.log") 2>&1
echo "# probe start $(date -u +%Y-%m-%dT%H:%M:%SZ)  BASE_URL=$BASE_URL  host=$(hostname)"

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

# ── §6.8 重現性探針：同 query、同參數，各 3 次 ─────────────────────────
# case06（醫美）與 case07（債務整合）是本輪最關鍵的兩題：
#   case07 在上一輪（v5.8）正是「把核心維度 debt_status 放寬掉」的案例，
#   而 v5.9 新增了 #57 核心維度保護 —— 所以「保護在重跑下是否都成立」必須量。
for i in 1 2 3; do
  probe "r06_aesthetic_${i}" "§6.8 重現性 — case06 醫美 r${i}/3" \
    --data-urlencode "questions=醫美診所的目標客戶" \
    --data-urlencode "role=醫美診所行銷主管" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done
for i in 1 2 3; do
  probe "r07_debt_${i}" "§6.8 重現性 — case07 債務整合 r${i}/3" \
    --data-urlencode "questions=債務整合貸款方案的目標客戶" \
    --data-urlencode "role=銀行債務整合專員" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done

# ── §6.9 定向探針 ────────────────────────────────────────────────────
# t1：極窄查詢 → matched=0 ⇒ 驗 #58 的 status 語意（matched==0 ⇔ status != 'ok'）
#     （主套件 9 案例全部 matched>0，完全涵蓋不到這條）
probe "t1_narrow_topk10" "§6.9 t1 極窄查詢 top_k=10 → matched=0 → #58 status 語意" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
# t2：同查詢 + top_k=100 → pool_exhausted=true 分支
probe "t2_narrow_topk100" "§6.9 t2 窄查詢 top_k=100 → pool_exhausted=true" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=100" \
  --data-urlencode "opMode=僅篩選"
# t3：TESLA + 較大 top_k → 逼放寬迴圈去動 commute_mode（#61 的保護維度）
#     ⇒ 驗「硬性 veto」路徑：attempt 應記 protected_veto + vetoed_dims，且 commute_mode 不得進 relaxed_dims
probe "t3_tesla_topk20" "§6.9 t3 TESLA top_k=20 → 逼出 protected_veto（#61 commute_mode）" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=20" \
  --data-urlencode "opMode=僅篩選"

echo ""
echo "# probe end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
touch "$P/PROBE_DONE"   # watcher 等這個檔，不用 pgrep（會 match 自己）
