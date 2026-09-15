#!/bin/bash
# round11 追加探針：case08（小吃攤老闆的目標客群 = 顧客語意）重跑 3 次
#
# 為什麼要追加：主套件的 case08 **誤套了 employment_status**（upstream 的 #34 斷言正確地發 ⚠️），
# 而且回傳名單與 case09（業主本人 B2B）重疊 9/10。這是語意方向的錯誤，不是數字偏差。
# 但 LLM 是不確定的 —— 單次失誤可能只是抽樣。**必須量它是否穩定**，
# 才知道該報成「穩定的語意誤判」還是「偶發」。
#
# OUT 自我定位（與 run-probe.sh 同）；證據獨立落盤到 probe/。

BASE_URL="${BASE_URL:-http://localhost:8000}"
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)}"
P="$OUT/probe"
mkdir -p "$P"
exec > >(tee -a "$P/probe08.log") 2>&1
echo "# probe08 start $(date -u +%Y-%m-%dT%H:%M:%SZ)  BASE_URL=$BASE_URL  host=$(hostname)  OUT=$OUT"

probe() {
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

# 與主套件 case08 完全相同的參數（questions / role / top_k / opMode 順序一致）
for i in 1 2 3; do
  probe "r08_boss_${i}" "追加探針 — case08 小吃攤（顧客語意）r${i}/3" \
    --data-urlencode "questions=小吃攤老闆的目標客群" \
    --data-urlencode "role=夜市商圈協會" \
    --data-urlencode "top_k=10" \
    --data-urlencode "opMode=僅篩選"
done

echo ""
echo "# probe08 end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
touch "$P/PROBE08_DONE"
