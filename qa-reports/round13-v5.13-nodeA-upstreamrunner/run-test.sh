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

# ── runner 環境（不改請求，只決定證據落盤位置）──────────────────────────
BASE_URL="${BASE_URL:-http://localhost:8000}"
OUT="${OUT:-$(cd "$(dirname "$0")" && pwd)}"
mkdir -p "$OUT"/{raw,json,headers,meta,extra,supplemental,probe}
exec > >(tee -a "$OUT/run.log") 2>&1
echo "# run start $(date -u +%Y-%m-%dT%H:%M:%SZ)  BASE_URL=$BASE_URL  host=$(hostname)"

# ── helper：一個案例 = 完整證據（raw body + headers + meta）─────────────
case_run() {   # case_run <id> <label 原文> <tmpname|-> <curl args...>
  local id="$1" label="$2" tmp="$3"
  shift 3
  echo ""
  echo "$label"
  time curl -s --get "${BASE_URL}/personadb/candidates" "$@" \
    -D "$OUT/headers/${id}.headers" -o "$OUT/raw/${id}.body" \
    -w 'http_code=%{http_code}\ntime_total=%{time_total}\nsize_download=%{size_download}\nurl_effective=%{url_effective}\n' > "$OUT/meta/${id}.w"
  {
    echo "# case  = ${id}"
    echo "# label = ${label}"
    echo "# cmd   = curl -s --get ${BASE_URL}/personadb/candidates $*"
    cat "$OUT/meta/${id}.w"
  } > "$OUT/meta/${id}.meta"
  cat "$OUT/raw/${id}.body" | tee "/tmp/${tmp}.json"
  echo ""
  cp "$OUT/raw/${id}.body" "$OUT/json/${id}.json" 2>/dev/null || true
}

# ── 案例 0：status（upstream 無標籤；此處僅為可讀性加一行）─────────────
echo ""
echo "=== 0. /personadb/status ==="
time curl -s --get "${BASE_URL}/personadb/status" \
  -D "$OUT/headers/00_status.headers" -o "$OUT/raw/00_status.body" \
  -w 'http_code=%{http_code}\ntime_total=%{time_total}\nsize_download=%{size_download}\nurl_effective=%{url_effective}\n' > "$OUT/meta/00_status.w"
{
  echo "# case  = 00_status"
  echo "# cmd   = curl -s --get ${BASE_URL}/personadb/status"
  cat "$OUT/meta/00_status.w"
} > "$OUT/meta/00_status.meta"
cat "$OUT/raw/00_status.body"

case_run "01_kangshimei" "=== 1. 康是美的目標客戶 ===（藥妝零售語意 — 不應套 aesthetic_procedure, #36）" "kangshimei" --data-urlencode "questions=康是美的目標客戶" --data-urlencode "top_k=3" --data-urlencode "opMode=僅篩選"

case_run "02_tesla" "=== 2. TESLA的目標客戶 ===" "tesla" --data-urlencode "questions=TESLA的目標客戶" --data-urlencode "top_k=3" --data-urlencode "opMode=僅篩選"

case_run "03_fashion" "=== 3. 時尚服裝設計師的目標客戶 ===" "fashion_closing" --data-urlencode "questions=時尚服裝設計師的目標客戶" --data-urlencode "top_k=10" --data-urlencode "opMode=僅篩選"

case_run "04_role_fangzhong" "=== 4. 房貸優惠 — 房仲業者 ===" "role_fangzhong" --data-urlencode "questions=房貸優惠方案" --data-urlencode "role=房仲業者" --data-urlencode "top_k=5" --data-urlencode "opMode=僅篩選"

case_run "05_role_banker" "=== 5. 房貸優惠 — 銀行業者 ===" "role_banker" --data-urlencode "questions=房貸優惠方案" --data-urlencode "role=銀行業者" --data-urlencode "top_k=5" --data-urlencode "opMode=僅篩選"

case_run "06_aesthetic" "=== 6. 醫美診所的目標客戶（dimension 20: aesthetic_procedure）===" "aesthetic_closing" --data-urlencode "questions=醫美診所的目標客戶" --data-urlencode "role=醫美診所行銷主管" --data-urlencode "top_k=10" --data-urlencode "opMode=僅篩選"

case_run "07_debt" "=== 7. 債務整合的目標客戶（dimension 21: debt_status）===" "debt_closing" --data-urlencode "questions=債務整合貸款方案的目標客戶" --data-urlencode "role=銀行債務整合專員" --data-urlencode "top_k=10" --data-urlencode "opMode=僅篩選"

case_run "08_boss" "=== 8. 小吃攤老闆的目標客群 — 【顧客語意】不應套 employment_status ===" "boss_closing" --data-urlencode "questions=小吃攤老闆的目標客群" --data-urlencode "role=夜市商圈協會" --data-urlencode "top_k=10" --data-urlencode "opMode=僅篩選"

case_run "09_owner" "=== 9. 業主本人 — dimension 22: employment_status（語意無歧義，issue #34）===" "owner_closing" --data-urlencode "questions=想找企業主或工廠老闆本人作為B2B問卷受訪者" --data-urlencode "top_k=10" --data-urlencode "opMode=僅篩選"

# ── 契約快照（本 runner 追加，供解讀回應用；不涉請求）────────────────
curl -s -m 30 "${BASE_URL}/openapi.json" -o "$OUT/raw/openapi.json"
echo ""
echo "# contract sha256: $(shasum -a 256 "$OUT/raw/openapi.json" 2>/dev/null | cut -d' ' -f1)"
echo "# run end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
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

echo ""
echo "=== Issue #34 / #35 / #37 checks ==="
python3 - <<'PYEOF'
import json, os

def load(p):
    try:
        return json.load(open(p))
    except Exception as e:
        print(f"  ⚠️  {p}: {e}")
        return {}

# ── #34: 業主語意 query 必須套 employment_status；顧客語意 query 不應套 ──
owner = load('/tmp/owner_closing.json')
boss = load('/tmp/boss_closing.json')
emp_o = (owner.get('applied_filters') or {}).get('employment_status')
emp_b = (boss.get('applied_filters') or {}).get('employment_status')
print(f"  #34 業主 query employment_status={emp_o} → " + ("✅" if emp_o else "❌ 未套用（must-use 指引失效）"))
print(f"  #34 顧客 query employment_status={emp_b} → " + ("✅ 未套用（語意正確）" if not emp_b else "⚠️ 誤套（顧客語意不該套）"))

# ── #35: dims_counted 必須涵蓋所有 applied_filters 維度（含新維度）──
for name, path in (('owner', '/tmp/owner_closing.json'),
                   ('aesthetic', '/tmp/aesthetic_closing.json'),
                   ('debt', '/tmp/debt_closing.json'),
                   ('boss', '/tmp/boss_closing.json')):
    d = load(path)
    af = set((d.get('applied_filters') or {}).keys())
    dc = set((d.get('scoring_basis') or {}).get('dims_counted') or [])
    if not af:
        continue
    missing = af - dc
    new_dims = sorted({'aesthetic_procedure', 'debt_status', 'employment_status'} & af)
    print(f"  #35 {name}: applied={len(af)} dims_counted={len(dc)} 新維度={new_dims or 'none'} "
          + ("✅" if not missing else f"❌ dims_counted 漏列 {sorted(missing)}"))

# ── #36: 非醫美語意不得套 aesthetic_procedure；醫美語意必須套 ──
aes_non = (load('/tmp/kangshimei.json').get('applied_filters') or {}).get('aesthetic_procedure')
aes_med = (load('/tmp/aesthetic_closing.json').get('applied_filters') or {}).get('aesthetic_procedure')
print(f"  #36 藥妝零售 query aesthetic_procedure={aes_non} → " + ("✅ 未套用" if not aes_non else "❌ 誤套（matched 會被限縮）"))
print(f"  #36 醫美 query aesthetic_procedure={aes_med} → " + ("✅ 正確套用" if aes_med else "❌ 未套用（修過頭）"))

# ── #37 / v5.4 #42: broadening_attempts 每筆都要有 no_op + overshoot 欄位 ──
for name, path in (('owner', '/tmp/owner_closing.json'),
                   ('kangshimei', '/tmp/kangshimei.json'),
                   ('tesla', '/tmp/tesla.json'),
                   ('aesthetic', '/tmp/aesthetic_closing.json'),
                   ('debt', '/tmp/debt_closing.json')):
    d = load(path)
    ba = d.get('broadening_attempts')
    if ba is None:
        continue
    ok = all(('no_op' in b and 'overshoot' in b) for b in ba)
    print(f"  #37/#42 {name}: {len(ba)} loops, no_op+overshoot 欄位" + ("✅" if ok else "❌ 缺"))

# ── v5.4 #42/#43/#44 斷言 ──
print("")
print("  --- v5.4 (#42/#43/#44) ---")
debt = load('/tmp/debt_closing.json')
af = debt.get('applied_filters') or {}
s = debt.get('summary') or []
have = [p for p in s if p.get('debt_status') in ('有房貸', '房貸+消費債', '有信貸或卡債')]
ovs = [b.get('overshoot') for b in (debt.get('broadening_attempts') or [])]
# #52: 比例式門檻（原為絕對 `>= 9`，在 pool_exhausted 只回 8 筆時 8/8 全對仍誤報 ⚠️）
# 保留原「容忍 1 筆」意圖（≥90%），且不假設池子大小；空池不得誤判通過
ratio_ok = ('debt_status' in af) and len(s) > 0 and (len(have) / len(s)) >= 0.9
print(f"  #42 debt_status 保留={('debt_status' in af)} 符合率={len(have)}/{len(s)} "
      f"({(len(have)/len(s)*100 if s else 0):.0f}%) pool_exhausted={debt.get('pool_exhausted')} overshoot={ovs} → "
      + ("✅" if ratio_ok else "⚠️ 檢查（被放寬、精度不足、或空池）"))
aes = load('/tmp/aesthetic_closing.json')
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

# ── v5.5 (#46/#47/#48/#49) 斷言（決定性、無 LLM 成本）──
print("")
print("  --- v5.5 (#47/#48/#49) ---")
import urllib.request, urllib.error
B = "http://localhost:8000"


def _raw(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


# #47: 錯誤回應必須是統一 ErrorResponse 形狀（不是 FastAPI 的 detail 包裝）
st, d = _raw(B + "/personadb/candidates?questions=x&opMode=%E4%BA%82%E5%AF%AB")
ok47 = st == 400 and isinstance(d.get("error"), dict) and "detail" not in d \
       and d["error"].get("code") == "INVALID_OPMODE"
print(f"  #47 400 錯誤形狀 status={st} code={(d.get('error') or {}).get('code')} 無 detail={('detail' not in d)} → "
      + ("✅" if ok47 else "❌ 契約不符"))
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

# ── v5.7 (#53/#54) 斷言：可篩維度必須可見（結構性，不受抽樣變異影響）──
print("")
print("  --- v5.7 (#53 summary 維度完備性 / #54 housing_cost) ---")
NEW_DIMS = ["sex", "region", "education", "marriage", "hobby", "politics", "media_diet"]
# 只使用本區塊之前已載入的案例變數（owner / boss / debt / aes）
_cases = {"醫美": aes, "債務": debt, "業主": owner, "小吃攤": boss}
_ok_fields = True
for cname, cd in _cases.items():
    rows = cd.get("summary") or []
    if not rows:
        print(f"  #53 {cname}: 無 summary（案例未產出？）→ ⚠️ 跳過")
        continue
    miss = [k for k in NEW_DIMS if k not in rows[0]]
    empty = [k for k in NEW_DIMS if k != "hobby" and any(not r.get(k) for r in rows)]
    bad_hobby = [r.get("id") for r in rows if not isinstance(r.get("hobby"), list)]
    good = (not miss) and (not empty) and (not bad_hobby)
    _ok_fields = _ok_fields and good
    print(f"  #53 {cname}: 7 欄位齊備={not miss} 無空值={not empty} hobby為list={not bad_hobby} → "
          + ("✅" if good else f"❌ 缺={miss} 空={empty} 非list={bad_hobby[:2]}"))
# 套用的新維度必須與回傳值一致（有套才驗）
for cname, cd in _cases.items():
    afx = cd.get("applied_filters") or {}
    rows = cd.get("summary") or []
    for dim in NEW_DIMS:
        if dim not in afx or not rows:
            continue
        want = set(afx[dim])
        ok = (all(want & set(r.get("hobby") or []) for r in rows) if dim == "hobby"
              else all(r.get(dim) in want for r in rows))
        print(f"  #53 {cname}: applied {dim}={afx[dim]} ↔ 回傳一致 → " + ("✅" if ok else "❌"))
#54：housing_cost 必須可篩（不再被靜默丟棄）—— LLM 是否選用依抽樣，故僅記錄不判定
_hc_seen = [c for c, cd in _cases.items() if "housing_cost" in (cd.get("applied_filters") or {})]
print(f"  #54 housing_cost 進入 applied_filters 的案例: {_hc_seen if _hc_seen else '（本輪未觸發，LLM 選用依抽樣）'}")

# ── v5.8 (#55/#56) 斷言：放寬停止原因 + 連續空轉上限 + 預算 ──
print("")
print("  --- v5.8 (#56 放寬停止原因 / #55 可診斷性) ---")
_ALLOWED_SR = {"", "target_reached", "no_op_limit", "loop_limit", "budget_limit",
               "llm_empty", "llm_parse_error", "llm_no_filters", "no_filters", "protected_veto"}
# v5.11：改為「動態以 OpenAPI enum 為準」（硬編清單曾在 v5.9 新增 protected_veto 後誤報；
# 以契約為準才不會隨版本腐化）—— 取不到時回退上面的靜態集合。
try:
    import urllib.request as _u56
    _os56 = json.load(_u56.urlopen("http://localhost:8000/openapi.json", timeout=10))
    _enum56 = set(_os56["components"]["schemas"]["CandidatesResponse"]
                  ["properties"]["broadening_stop_reason"]["enum"])
    if _enum56:
        _ALLOWED_SR = _enum56
        print(f"  #56 停止原因白名單取自 OpenAPI enum（{len(_enum56)} 值）")
except Exception as _e56:
    print(f"  #56 OpenAPI 不可用（{type(_e56).__name__}）→ 使用靜態白名單")
for cname, cd in _cases.items():
    rows = cd.get("summary") or []
    if not rows and not cd.get("broadening_attempts"):
        continue
    sr = cd.get("broadening_stop_reason", None)
    ba = cd.get("broadening_attempts") or []
    if sr is None:
        print(f"  #56 {cname}: 回應缺 broadening_stop_reason 欄位 → ❌")
        continue
    ok_sr = sr in _ALLOWED_SR
    # 契約不變式（v5.9 起）：受保護維度不得出現在 relaxed_dims（與 stop_reason 無關）
    if set(cd.get("protected_dims") or []) & set(cd.get("relaxed_dims") or []):
        ok_sr = False
        print(f"  #56 {cname}: ⚠️ protected ∩ relaxed 非空 → 不變式違反")
    # 連續 no_op 上限 ≤ 2
    streak = mx = 0
    for b in ba:
        streak = streak + 1 if b.get("no_op") else 0
        mx = max(mx, streak)
    ok_streak = mx <= 2
    # 一致性：no_op_limit ⇒ 最後一輪必為 no_op（兩條路徑：① 連續 2 輪空轉 ② filters 未變更
    # （LLM 原樣回傳）→ 前者最後兩輪皆 no_op，後者僅最後一輪）；target_reached ⇒ matched ≥ 20
    consistent = True
    if sr == "no_op_limit":
        consistent = bool(ba) and ba[-1].get("no_op") is True
    elif sr == "target_reached":
        consistent = (cd.get("total_matched") or 0) >= 20
    print(f"  #56 {cname}: stop_reason={sr!r} loops={len(ba)} 連續空轉max={mx} → "
          + ("✅" if (ok_sr and ok_streak and consistent) else f"❌ (合法={ok_sr} 空轉={ok_streak} 一致={consistent})"))
_sr_seen = sorted({cd.get("broadening_stop_reason") for cd in _cases.values()})
print(f"  #56 本輪出現的停止原因: {_sr_seen}")

# ── v5.9 (#57/#58/#59) 斷言：核心維度保護 + status 語意 + 契約 ──
print("  --- v5.9 (#57 核心維度保護 / #58 status / #59 503 兩型態) ---")
_ALLOWED_SR_V59 = {"", "target_reached", "no_op_limit", "loop_limit", "budget_limit",
                   "llm_empty", "llm_parse_error", "llm_no_filters", "no_filters", "protected_veto"}
_missing_field = [c for c, cd in _cases.items() if "protected_dims" not in cd]
print(f"  #57 全部案例都有 protected_dims 欄位 → " + ("✅" if not _missing_field else f"❌ 缺 {_missing_field}"))
print(f"  #57 本輪各案保護集: " + "; ".join(
    f"{c}={cd.get('protected_dims')}" for c, cd in _cases.items()))
# ★ 不變式：受保護維度不得出現在 relaxed_dims
_viol = {c: sorted(set(cd.get("protected_dims") or []) & set(cd.get("relaxed_dims") or []))
         for c, cd in _cases.items()}
_viol = {c: v for c, v in _viol.items() if v}
print(f"  ★ #57 不變式（受保護維度未被放寬）→ " + ("✅" if not _viol else f"❌ {_viol}"))
# protected_veto 兩條路徑（見下方迴圈）
_bad_veto = []
for c, cd in _cases.items():
    if cd.get("broadening_stop_reason") != "protected_veto":
        continue
    _ba = cd.get("broadening_attempts") or []
    # 兩條路徑（#57/#59）：① 硬性 veto（attempt 記 protected_veto + vetoed_dims）
    #                     ② 模型自行拒絕（最後一輪 no_op=true 且 filters 未變更）
    _p1 = any(b.get("protected_veto") and b.get("vetoed_dims") for b in _ba)
    _p2 = bool(_ba) and bool(_ba[-1].get("no_op")) and not _ba[-1].get("filters_changed")
    if not (_p1 or _p2):
        _bad_veto.append(c)
print(f"  #57 protected_veto 符合其一條路徑（硬性 veto 或模型拒絕）→ " + ("✅" if not _bad_veto else f"❌ {_bad_veto}"))
_sr_seen_v59 = sorted({cd.get("broadening_stop_reason") for cd in _cases.values()})
if "protected_veto" not in _sr_seen_v59:
    print("  #57 本輪未觸發 veto（保護維度皆未被嘗試移除）→ ℹ️")
# veto 的三條延伸不變式（來源：round10 §3.1 的 K/L/M — 由 dsh1 提出，我方採納為出貨斷言）
_k = _l = _m = []
for c, cd in _cases.items():
    _prot = set(cd.get("protected_dims") or [])
    for b in (cd.get("broadening_attempts") or []):
        if not b.get("protected_veto"):
            continue
        if not set(b.get("vetoed_dims") or []) <= _prot:
            _k.append(c)                                    # K: vetoed_dims ⊆ protected_dims
        if not (b.get("vetoed_dims") or []):
            _l.append(c)                                    # L: veto 必有非空 vetoed_dims
        if not (b.get("no_op") and not b.get("filters_changed")   # M: veto 必須是 rollback
                and b.get("match_count_before") == b.get("match_count_after")):
            _m.append(c)
print("  #57 veto 不變式 K（vetoed_dims ⊆ protected_dims）→ " + ("✅" if not _k else f"❌ {sorted(set(_k))}"))
print("  #57 veto 不變式 L（veto 必有非空 vetoed_dims）→ " + ("✅" if not _l else f"❌ {sorted(set(_l))}"))
print("  #57 veto 不變式 M（veto 是 rollback：no_op 且 filters 未變更且計數不變）→ " + ("✅" if not _m else f"❌ {sorted(set(_m))}"))
# 空值清單守門（#62）：applied_filters 的值清單不得為空（空清單 = 排除全部，語意陷阱）
_empty = {c: [k2 for k2, v2 in (cd.get("applied_filters") or {}).items() if isinstance(v2, list) and not v2]
          for c, cd in _cases.items()}
_empty = {c: v2 for c, v2 in _empty.items() if v2}
print("  #62 applied_filters 無空值清單（空清單＝排除全部）→ " + ("✅" if not _empty else f"❌ {_empty}"))
# #63：值集放寬的留痕（v5.11.1 起：放寬＝合法、只留痕；故僅資訊性呈現，不判定 ❌）
_wd = {}
for c, cd in _cases.items():
    wide = set()
    for b in (cd.get("broadening_attempts") or []):
        wide |= set(b.get("widened_dims") or [])
    if wide:
        _wd[c] = sorted(wide)
print(f"  #63 本輪值集放寬留痕: {_wd if _wd else '（無）'}")
_n_wide = sum(1 for cd in _cases.values() for b in (cd.get("broadening_attempts") or []) if b.get("widened_dims"))
print(f"  #63 widened_dims 留痕輪數: {_n_wide}（放寬為合法行為；此欄位供稽核）")
# #58 status 語意：matched==0 ⇔ status != 'ok'
_bad_status = [c for c, cd in _cases.items()
               if ((cd.get("total_matched") or 0) == 0) != (cd.get("status") != "ok")]
print(f"  #58 status 語意（matched==0 ⇔ status!=ok）→ " + ("✅" if not _bad_status else f"❌ {_bad_status}"))
# #59 列舉：protected_veto 存在（OpenAPI 零成本檢查）
try:
    import urllib.request as _u
    _os = json.load(_u.urlopen("http://localhost:8000/openapi.json", timeout=10))
    _props = _os["components"]["schemas"]["CandidatesResponse"]["properties"]
    _enum = _props["broadening_stop_reason"]["enum"]
    print("  #59 OpenAPI 含 protected_dims → " + ("✅" if "protected_dims" in _props else "❌"))
    print("  #59 stop_reason enum 含 protected_veto → " + ("✅" if "protected_veto" in _enum else "❌"))
    _bad_enum = [v for v in _sr_seen_v59 if v not in _enum]
    print(f"  #59 回應出的停止原因皆在 enum 內 → " + ("✅" if not _bad_enum else f"❌ {_bad_enum}"))
except Exception as e:
    print(f"  #59 OpenAPI 檢查失敗（非致命）: {type(e).__name__}")

# ── v5.10 (#60 root logger / #61 protect-only) 斷言 ──
print("  --- v5.10 (#61 commute_mode 保護) ---")
_tesla = load('/tmp/tesla.json')
if _tesla:
    _tp = _tesla.get('protected_dims') or []
    _tr = _tesla.get('relaxed_dims') or []
    print(f"  #61 TESLA protected={_tp} relaxed={_tr}")
    print("  #61 TESLA 保護集含 commute_mode → " + ("✅" if "commute_mode" in _tp else "❌"))
    print("  #61 TESLA 未放寬 commute_mode → " + ("✅" if "commute_mode" not in _tr else "❌"))
else:
    print("  #61 TESLA 案例檔缺失 → ⚠️（無法驗證）")

# ── v5.12 (#65 主體判準 / forbidden / 揭露) 斷言 ──
print("  --- v5.12 (#65 顧客 vs 業主語意護欄) ---")
_nosubj = [c for c, cd in _cases.items() if "subject" not in cd]
print("  #65 所有案例都有 subject/warnings 欄位 → " + ("✅" if not _nosubj else f"❌ 缺 {_nosubj}"))
_boss_cd = load('/tmp/boss_closing.json') or _cases.get("小吃攤") or {}
_owner_cd = load('/tmp/owner_closing.json') or _cases.get("業主") or {}
if _boss_cd:
    _bef = _boss_cd.get("applied_filters") or {}
    print(f"  #65 顧客案例（小吃攤）: subject={_boss_cd.get('subject')!r} "
          f"applied={list(_bef)} warnings={_boss_cd.get('warnings')}")
    print("  #65 顧客語意未套 employment_status → "
          + ("✅" if "employment_status" not in _bef else "❌ 仍被套用！"))
    print("  #65 顧客案例 subject='customer' → "
          + ("✅" if _boss_cd.get("subject") == "customer" else f"❌ {_boss_cd.get('subject')!r}"))
    print("  #65 顧客語意 protected 不含 employment_status → "
          + ("✅" if "employment_status" not in (_boss_cd.get("protected_dims") or []) else "❌"))
else:
    print("  #65 顧客案例檔缺失 → ⚠️（無法驗證）")
if _owner_cd:
    _oaf = _owner_cd.get("applied_filters") or {}
    print("  #65 業主案例（#34 must-use 不回歸）: subject=%r 套用=%s → "
          % (_owner_cd.get("subject"), _oaf.get("employment_status"))
          + ("✅" if (_owner_cd.get("subject") == "owner"
                      and _oaf.get("employment_status")) else "❌"))

# ── S'/T 不變式（**掃描全部 9 案例**）──
# 形式更正：round11 §3.2 的原始提案是「嚴格形式」（widened ⊆ applied、widened ∩ relaxed = ∅），
# 但**同一份報告的 §5.10／§6.4 已更正**該形式會對合法跨輪序列誤報；round12 §3.1 以 05_role_banker
# 提供了新實例（loop2 放寬 income 值集 → loop3 因已無篩選效果而移除 income）。
# 正確形式：`widened ⊆ applied ∪ relaxed`；「既放寬又被移除」＝合法、僅列資訊性。
# 教訓（我方）：採納外部不變式時，必須同時讀該報告的「更正」與「限制」章節，不能只讀那張表。
_ALL9 = [("01 康是美", "/tmp/kangshimei.json"), ("02 TESLA", "/tmp/tesla.json"),
         ("03 時尚", "/tmp/fashion_closing.json"), ("04 房仲", "/tmp/role_fangzhong.json"),
         ("05 銀行", "/tmp/role_banker.json"), ("06 醫美", "/tmp/aesthetic_closing.json"),
         ("07 債務", "/tmp/debt_closing.json"), ("08 小吃攤", "/tmp/boss_closing.json"),
         ("09 業主", "/tmp/owner_closing.json")]
_s_bad, _both, _scanned = [], [], 0
for _lab, _p in _ALL9:
    _d = load(_p)
    if not _d:
        continue
    _scanned += 1
    _af = set(_d.get("applied_filters") or {})
    _rel = set(_d.get("relaxed_dims") or [])
    _wide = set()
    for b in (_d.get("broadening_attempts") or []):
        _wide |= set(b.get("widened_dims") or [])
    if _wide - (_af | _rel):
        _s_bad.append((_lab, sorted(_wide - (_af | _rel))))     # S': widened ⊆ applied ∪ relaxed
    if _wide & _rel:
        _both.append((_lab, sorted(_wide & _rel)))              # 合法序列 → 資訊性
print(f"  #63 不變式 S'（widened_dims ⊆ applied_filters ∪ relaxed_dims；掃描 {_scanned}/9 案例）→ "
      + ("✅" if not _s_bad else f"❌ {_s_bad}"))
print(f"  #63 既放寬又被移除（合法，資訊性）: {_both if _both else '（本輪無）'}")

# 同質化矩陣（語意反轉的指紋）：**全部 9 案例**回傳名單兩兩重疊
import itertools
_names = {}
for _lab, _p in _ALL9:
    _d = load(_p)
    if _d:
        _names[_lab] = set(_d.get("persona_ids") or [])
_hi = []
for (_a, _sa), (_b, _sb) in itertools.combinations(sorted(_names.items()), 2):
    if _sa and _sb:
        _ov = len(_sa & _sb)
        if _ov >= 8:
            _hi.append((_a, _b, _ov))
print(f"  #65 同質化矩陣（{len(_names)}/9 案例兩兩重疊）: " +
      (f"⚠️ 高度重疊配對 {_hi}（語意反轉指紋，需人工確認）" if _hi else "✅ 無 ≥8/10 的配對"))

# ── v5.13 (#66 保護集上限/揭露、#67 主體覆蓋/依據) 斷言 ──
print("  --- v5.13 (#66 保護集上限與揭露 / #67 主體覆蓋與依據) ---")
_missing13, _cap_bad, _src_bad, _sat_ok = [], [], [], True
for _lab, _p in _ALL9:
    _d = load(_p)
    if not _d:
        continue
    for _k in ("subject_basis", "protected_dims_sources"):
        if _k not in _d:
            _missing13.append((_lab, _k))
    _src = _d.get("protected_dims_sources") or {}
    if _src and set(_src) != {"domain", "reasoning", "analysis_declared", "model_declared", "protect_only"}:
        _src_bad.append((_lab, sorted(_src)))
    # #66 A 上限：產品以**請求開始**的已套用維度數算上限（回應不含該基準，且 applied_filters 會變動）
    # → 出貨斷言只驗**硬上限 DECLARED_PROTECTED_MAX=3**；半數規則由單元測試以已知 filter 數驗證。
    _md = _src.get("model_declared") or []
    if len(_md) > 3:
        _cap_bad.append((_lab, len(_md)))
print("  #67 B 所有案例都有 subject_basis/protected_dims_sources → " + ("✅" if not _missing13 else f"❌ {_missing13}"))
print("  #66 A protected_dims_sources 五鍵齊全 → " + ("✅" if not _src_bad else f"❌ {_src_bad}"))
print("  #66 A 來源④ 數量 ≤ 硬上限 3 → " + ("✅" if not _cap_bad else f"❌ {_cap_bad}"))
_boss13 = _cases.get("boss")
if _boss13:
    print(f"  #67 顧客案例 subject_basis: {(_boss13.get('subject_basis') or '')[:52]!r} → "
          + ("✅" if _boss13.get("subject_basis") else "❌"))
# #66 C：protection_saturated 在 enum 內（靜態檢查；實際觸發需全維度受保護，套件通常不會出現）
_enum13 = set()
try:
    import urllib.request as _u
    _spec = json.loads(_u.urlopen("http://localhost:8000/openapi.json", timeout=10).read())
    _enum13 = set((_spec.get("components", {}).get("schemas", {})
                   .get("CandidatesResponse", {}).get("properties", {})
                   .get("broadening_stop_reason", {}).get("enum") or []))
except Exception:
    pass
print("  #66 C enum 含 protection_saturated → " + ("✅" if "protection_saturated" in _enum13 else f"❌ {sorted(_enum13)}"))
PYEOF

# ── #60：app 的 INFO 行是否真的進 log（root logger 設定生效）──
_n_info=$(sudo docker logs persona-db-api 2>&1 | grep -c "Protected dims")
_n_broad=$(sudo docker logs persona-db-api 2>&1 | grep -c "Broadening loop")
echo "  --- v5.10 (#60 root logger) ---"
echo "  #60 app INFO 行：Protected dims=${_n_info} ｜ Broadening loop=${_n_broad}"
if [ "${_n_info}" -gt 0 ] || [ "${_n_broad}" -gt 0 ]; then
  echo "  #60 INFO 行已進 log（root logger 設定生效）→ ✅"
else
  echo "  #60 INFO 行 0 筆 → ⚠️（檢查 LOG_LEVEL 是否為 WARNING，或映像為舊版）"
fi
printf "  #60 容器 LOG_LEVEL: "
sudo docker exec persona-db-api sh -c 'grep LOG_LEVEL /app/.env' 2>/dev/null || echo "(未設定 → 預設 INFO)"

# #55：失敗 log 需帶例外型別（主機層：確認映像內 code 有該診斷）
if sudo docker exec persona-db-api grep -q "LLM call failed \[" /app/api/llm.py 2>/dev/null; then
  echo "  #55 映像含例外型別診斷碼（LLM call failed [Type]）→ ✅"
else
  echo "  #55 映像缺例外型別診斷碼 → ⚠️（stale 映像？）"
fi
echo ""
echo "  --- v5.6 (#50) / 部署版本一致性 ---"
# #50: 部署映像必須是含 finish_reason 診斷碼的版本（避免 stale 映像通過測試）
DEPLOYED_VER=$(sudo docker exec persona-db-api cat /app/VERSION 2>/dev/null | tr -d '\r\n')
REPO_VER=$(cat "$(dirname "$0")/RELEASE-VERSION" 2>/dev/null | tr -d '\r\n')
if [ -n "$DEPLOYED_VER" ] && [ "$DEPLOYED_VER" = "$REPO_VER" ]; then
  echo "  部署版本 == RELEASE-VERSION ($DEPLOYED_VER) → ✅"
else
  echo "  部署版本 ($DEPLOYED_VER) != RELEASE-VERSION ($REPO_VER) → ⚠️ 可能是 stale 映像"
fi
if sudo docker exec persona-db-api grep -q "finish_reason={fr}" /app/api/llm.py 2>/dev/null; then
  echo "  #50 映像含 finish_reason 診斷碼（解析失敗 log 可直接判讀截斷）→ ✅"
else
  echo "  #50 映像缺 finish_reason 診斷碼 → ⚠️"
fi
