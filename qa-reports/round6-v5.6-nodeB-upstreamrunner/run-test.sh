#!/bin/bash
# Round 6 runner — adapted from upstream `upDockerVerHermes/test-persona-db-api.sh`
#   upstream sha256: 9a29a8ef3bc553a334b1865c792d4f0f17e60ce15f93a46fe9f8ac9b684edbd8  (223 行, 2026-09-14 取得)
#
# 為什麼換 runner（2026-09-14, issue #51 / CORRECTIONS.md 修正③）:
#   前五輪共用第一輪凍結的 runner（上游副本 33749d4e…, 90 行），其案例集**不含「業主本人」語意案例**，
#   導致 `employment_status` 每輪被誤報 0/8。本輪改用現行上游（223 行）＝新 baseline。
#
# 依 api-version-sweep Step 1 的改動紀律：
#   可以改 → base URL、輸出目錄、證據落盤、解析工具
#   不可改 → 請求參數、參數順序、斷言邏輯   ← 下列全部照上游原樣
#
# 遠端限制：上游的 #50 用 `sudo docker exec <container>` 讀容器內檔案，**遠端無法執行** →
#   本 runner 記為 N/A 並明確輸出，不假裝通過。

set -u

BASE_URL="${BASE_URL:?BASE_URL required, e.g. http://NODE-B:8000}"
OUT="${OUT:?OUT required}"
mkdir -p "$OUT/raw" "$OUT/json" "$OUT/headers" "$OUT/meta" "$OUT/extra"

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq not found — installing..."
  sudo apt-get install -y jq >/dev/null 2>&1 || { echo "❌ jq install failed, case 3 will fail"; }
fi

case_run() {   # case_id label url [curl args...]
  local id="$1"; shift
  local label="$1"; shift
  local url="$1"; shift

  echo ""
  echo "=== ${label} ==="
  echo "--- REQUEST: GET ${url} $* ---"

  time curl -s --get "$url" "$@" \
    -D "$OUT/headers/${id}.headers" \
    -o "$OUT/raw/${id}.body" \
    -w '%{http_code}\t%{time_total}\t%{size_download}\t%{url_effective}\n' \
    > "$OUT/meta/${id}.w"

  local code sec size eff
  code=$(cut -f1 "$OUT/meta/${id}.w"); sec=$(cut -f2 "$OUT/meta/${id}.w")
  size=$(cut -f3 "$OUT/meta/${id}.w"); eff=$(cut -f4 "$OUT/meta/${id}.w")

  { echo "case_id: ${id}"; echo "label: ${label}"; echo "http_code: ${code}"
    echo "time_total_sec: ${sec}"; echo "size_download_bytes: ${size}"
    echo "url_effective: ${eff}"; echo "curl_args: $*"; } > "$OUT/meta/${id}.meta"

  echo "--- HTTP ${code} | ${sec}s | ${size} bytes ---"
  echo "--- RESPONSE BODY ---"
  cat "$OUT/raw/${id}.body"
  echo ""

  if jq . "$OUT/raw/${id}.body" > "$OUT/json/${id}.json" 2>"$OUT/meta/${id}.jqerr"; then
    rm -f "$OUT/meta/${id}.jqerr"
    echo "--- (pretty JSON saved: json/${id}.json) ---"
  else
    echo "--- (NOT valid JSON — see meta/${id}.jqerr) ---"
    cat "$OUT/meta/${id}.jqerr"
  fi
}

echo "############################################################"
echo "# persona-db API 實測 — 第六輪（upstream runner 9a29a8ef）"
echo "# BASE_URL = ${BASE_URL}"
echo "# started  = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "############################################################"

# --- 0. status（上游 line 17）---
case_run "00_status" "0. /personadb/status" "${BASE_URL}/personadb/status"

# --- 1.（上游 line 20-24；標籤含 #36 語意註記）---
case_run "01_kangshimei" "1. 康是美的目標客戶 ===（藥妝零售語意 — 不應套 aesthetic_procedure, #36）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=康是美的目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"

# --- 2.（上游 line 27-31）---
case_run "02_tesla" "2. TESLA的目標客戶" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"

# --- 3.（上游 line 34-38）---
case_run "03_fashion" "3. 時尚服裝設計師的目標客戶" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=時尚服裝設計師的目標客戶" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# --- 4.（上游 line 42-47）---
case_run "04_role_fangzhong" "4. 房貸優惠 — 房仲業者" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=房貸優惠方案" \
  --data-urlencode "role=房仲業者" \
  --data-urlencode "top_k=5" \
  --data-urlencode "opMode=僅篩選"

# --- 5.（上游 line 50-55）---
case_run "05_role_banker" "5. 房貸優惠 — 銀行業者" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=房貸優惠方案" \
  --data-urlencode "role=銀行業者" \
  --data-urlencode "top_k=5" \
  --data-urlencode "opMode=僅篩選"

# --- 6.（上游 line 58-63）---
case_run "06_aesthetic" "6. 醫美診所的目標客戶（dimension 20: aesthetic_procedure）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=醫美診所的目標客戶" \
  --data-urlencode "role=醫美診所行銷主管" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# --- 7.（上游 line 66-71）---
case_run "07_debt" "7. 債務整合的目標客戶（dimension 21: debt_status）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=債務整合貸款方案的目標客戶" \
  --data-urlencode "role=銀行債務整合專員" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# --- 8.（上游 line 74-79；標籤已改為顧客語意）---
case_run "08_boss" "8. 小吃攤老闆的目標客群 — 【顧客語意】不應套 employment_status" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=小吃攤老闆的目標客群" \
  --data-urlencode "role=夜市商圈協會" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# --- 9. ★新案例（上游 line 82-86）---
case_run "09_owner" "9. 業主本人 — dimension 22: employment_status（語意無歧義，issue #34）" "${BASE_URL}/personadb/candidates" \
  --data-urlencode "questions=想找企業主或工廠老闆本人作為B2B問卷受訪者" \
  --data-urlencode "top_k=10" \
  --data-urlencode "opMode=僅篩選"

# --- Role QA: diff check（上游 line 89-97；改用 jq 讀已落盤檔案，等效）---
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

# --- Issue #34/#35/#36/#37 + v5.4 #42/#43/#44 斷言（上游 line 100-208；邏輯原樣，僅路徑改為 $OUT）---
echo ""
echo "=== Issue #34 / #35 / #36 / #37 checks ==="
OUT="$OUT" python3 - <<'PYEOF' | tee "$OUT/extra/assertions-34-37.txt"
import json, os
OUT = os.environ['OUT']

def load(n):
    p = os.path.join(OUT, 'json', n + '.json')
    try:
        return json.load(open(p))
    except Exception as e:
        print(f"  ⚠️  {n}: {e}")
        return {}

# ── #34: 業主語意 query 必須套 employment_status；顧客語意 query 不應套 ──
owner = load('09_owner')
boss = load('08_boss')
emp_o = (owner.get('applied_filters') or {}).get('employment_status')
emp_b = (boss.get('applied_filters') or {}).get('employment_status')
print(f"  #34 業主 query employment_status={emp_o} → " + ("✅" if emp_o else "❌ 未套用（must-use 指引失效）"))
print(f"  #34 顧客 query employment_status={emp_b} → " + ("✅ 未套用（語意正確）" if not emp_b else "⚠️ 誤套（顧客語意不該套）"))

# ── #35: dims_counted 必須涵蓋所有 applied_filters 維度（含新維度）──
for name in ('09_owner', '06_aesthetic', '07_debt', '08_boss'):
    d = load(name)
    af = set((d.get('applied_filters') or {}).keys())
    dc = set((d.get('scoring_basis') or {}).get('dims_counted') or [])
    if not af:
        continue
    missing = af - dc
    new_dims = sorted({'aesthetic_procedure', 'debt_status', 'employment_status'} & af)
    print(f"  #35 {name}: applied={len(af)} dims_counted={len(dc)} 新維度={new_dims or 'none'} "
          + ("✅" if not missing else f"❌ dims_counted 漏列 {sorted(missing)}"))

# ── #36: 非醫美語意不得套 aesthetic_procedure；醫美語意必須套 ──
aes_non = (load('01_kangshimei').get('applied_filters') or {}).get('aesthetic_procedure')
aes_med = (load('06_aesthetic').get('applied_filters') or {}).get('aesthetic_procedure')
print(f"  #36 藥妝零售 query aesthetic_procedure={aes_non} → " + ("✅ 未套用" if not aes_non else "❌ 誤套（matched 會被限縮）"))
print(f"  #36 醫美 query aesthetic_procedure={aes_med} → " + ("✅ 正確套用" if aes_med else "❌ 未套用（修過頭）"))

# ── #37 / v5.4 #42: broadening_attempts 每筆都要有 no_op + overshoot 欄位 ──
for name in ('09_owner', '01_kangshimei', '02_tesla', '06_aesthetic', '07_debt'):
    d = load(name)
    ba = d.get('broadening_attempts')
    if ba is None:
        continue
    ok = all(('no_op' in b and 'overshoot' in b) for b in ba)
    print(f"  #37/#42 {name}: {len(ba)} loops, no_op+overshoot 欄位" + ("✅" if ok else "❌ 缺"))

# ── v5.4 #42/#43/#44 斷言 ──
print("")
print("  --- v5.4 (#42/#43/#44) ---")
debt = load('07_debt')
af = debt.get('applied_filters') or {}
s = debt.get('summary') or []
have = [p for p in s if p.get('debt_status') in ('有房貸', '房貸+消費債', '有信貸或卡債')]
ovs = [b.get('overshoot') for b in (debt.get('broadening_attempts') or [])]
print(f"  #42 debt_status 保留={('debt_status' in af)} 符合率={len(have)}/{len(s)} overshoot={ovs} → "
      + ("✅" if ('debt_status' in af and len(have) >= 9) else "⚠️ 檢查（可能被放寬或精度不足）"))
aes = load('06_aesthetic')
af_a = aes.get('applied_filters') or {}
print(f"  #42 醫美硬篩選維持: sex={af_a.get('sex')} aesthetic={af_a.get('aesthetic_procedure')} → "
      + ("✅" if af_a.get('aesthetic_procedure') else "⚠️"))
print(f"  #43 案例06 returned={aes.get('returned')} pool_exhausted={aes.get('pool_exhausted')} "
      f"len(summary)={len(aes.get('summary') or [])} → "
      + ("✅" if aes.get('returned') == len(aes.get('summary') or []) else "❌ returned 與實際不符"))
sb = (aes.get('scoring_basis') or {})
print(f"  #44 weight_version={sb.get('weight_version')} score_scale={sb.get('score_scale')} "
      f"score_schema={sb.get('score_schema')} → "
      + ("✅" if sb.get('weight_version') and sb.get('score_scale') == 'relative-within-version' else "❌ 缺欄位"))
PYEOF

# --- v5.5 #46/#47/#48/#49 斷言（上游 line 175-207；B 改為 $BASE_URL，邏輯原樣）---
echo ""
echo "  --- v5.5 (#47/#48/#49) ---"
OUT="$OUT" BASE_URL="$BASE_URL" python3 - <<'PYEOF' | tee "$OUT/extra/assertions-47-49.txt"
import json, os, urllib.request, urllib.error
OUT = os.environ['OUT']; B = os.environ['BASE_URL']

def _raw(url):
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)

# #47: 錯誤回應必須是統一 ErrorResponse 形狀（不是 FastAPI 的 detail 包裝）
st, d = _raw(B + "/personadb/candidates?questions=x&opMode=%E4%BA%82%E5%AF%AB")
print(f"  #47 400 錯誤形狀 status={st} body={json.dumps(d, ensure_ascii=False)[:160]}")
ok47 = st == 400 and isinstance(d.get("error"), dict) and "detail" not in d \
       and d["error"].get("code") == "INVALID_OPMODE"
print(f"  #47 → " + ("✅ 契約相符" if ok47 else "❌ 契約不符（宣告 ErrorResponse 但實際不同）"))
json.dump({"status": st, "body": d}, open(os.path.join(OUT, 'extra', 'assert47-invalid-opmode.json'), 'w'),
          ensure_ascii=False, indent=2)

st, spec = _raw(B + "/openapi.json")
# #49: opMode 的 default 必須是合法值（修復前是 '兩者皆可' → 省略即 400）
opm = [p for p in spec["paths"]["/personadb/candidates"]["get"]["parameters"] if p["name"] == "opMode"][0]
dflt = opm["schema"].get("default")
print(f"  #49 opMode 預設值={dflt!r} 在合法清單內 → "
      + ("✅" if dflt in ("僅篩選", "篩選+模擬", "模擬詢問") else "❌ 預設值不合法（省略 opMode 會 400）"))
# #48: 可觀測性欄位要有機器可讀 schema
sch = spec.get("components", {}).get("schemas", {})
ok48 = ("BroadeningAttempt" in sch and "ScoringBasis" in sch
        and "overshoot" in sch["BroadeningAttempt"]["properties"]
        and "score_scale" in sch["ScoringBasis"]["properties"])
print(f"  #48 OpenAPI 有 BroadeningAttempt/ScoringBasis 且 properties 完整 → " + ("✅" if ok48 else "❌"))
PYEOF

# --- v5.6 #50（上游 line 210-223）---
echo ""
echo "  --- v5.6 (#50) / 部署版本一致性 ---"
echo "  #50 N/A — 上游此項用 'sudo docker exec <container>' 讀容器內檔案，本 runner 為**遠端 HTTP 執行**，無 host 權限。"
echo "       未執行 ≠ 通過；需在受測主機上跑上游原版才能驗此項。"
{ echo "assertion: #50 部署版本一致性 / finish_reason 診斷碼"
  echo "status: N/A（not executed)"; echo "reason: 需要 host 端 'sudo docker exec'，遠端 runner 無此權限"; } > "$OUT/extra/assert50-na.txt"

echo ""
echo "# finished = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
