#!/bin/bash
# §6.8 重現性探針 + §6.9 定向探針
# 必須在主套件「跑完之後」才執行 —— 併跑會互相影響延遲量測。
# 證據獨立落盤到 probe/（不與主套件混用），並在報告標明「主套件未涵蓋此分支」。

BASE_URL="${BASE_URL:-http://localhost:8000}"
OUT="${OUT:-$HOME/qa-round9}"
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
  echo "  → $(cat "$P/${id}.w" | tr '\n' ' ')"
}

# ── §6.8 重現性探針：同一 query、同一參數，重複 3 次 ──────────────────
# case06（醫美）與 case09（業主）是本輪 §6.2/§6.3/§6.4 與 must-use 判定的主要依據，
# 所以「我的結論是否只是雜訊的一次抽樣」要在這兩題上量。
for i in 1 2 3; do
  probe "r06_aesthetic_${i}" "§6.8 重現性 — case06 醫美 r${i}/3" \
    --data-urlencode "questions=醫美診所的目標客戶" \
    --data-urlencode "role=醫美診所行銷主管" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done
for i in 1 2 3; do
  probe "r09_owner_${i}" "§6.8 重現性 — case09 業主 r${i}/3" \
    --data-urlencode "questions=想找企業主或工廠老闆本人作為B2B問卷受訪者" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done

# ── §6.9 定向探針：逼出主套件「不必然觸發」的分支 ─────────────────────
# 契約宣告的 broadening_stop_reason 有 8 個非空值。主套件只會涵蓋其中一部分，
# 光看主套件無法確認其他分支會不會動。設計「必然觸發」的請求：
#
# t1：極窄查詢 → 3 輪放寬後仍 < TARGET_MIN(20) → 期望 loop_limit / no_op_limit
#     （主套件幾乎都是 target_reached）
# t2：同窄查詢 + top_k=100 → matched < top_k → 期望 pool_exhausted=true
# t3：極寬查詢 → 首次篩選即 ≥ TARGET_MIN → 迴圈不進入 → 期望 stop_reason=""（空字串分支）
probe "t1_narrow_topk10" "§6.9 t1 窄查詢 → 非 target_reached 停止原因" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"
probe "t2_narrow_topk100" "§6.9 t2 窄查詢 + top_k=100 → pool_exhausted=true 分支" \
  --data-urlencode "questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主" \
  --data-urlencode "top_k=100" \
  --data-urlencode "opMode=僅篩選"
probe "t3_broad_topk3" "§6.9 t3 極寬查詢 → stop_reason 空字串分支（未進入迴圈）" \
  --data-urlencode "questions=目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"

echo ""
echo "# probe end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
# 完成標記：watcher 用「等這個檔案」而不是 pgrep（pgrep -f 會 match watcher 自己的 cmdline）
touch "$P/PROBE_DONE"
