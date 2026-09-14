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

# 正確版 ✅ — 中文自動 URL encode

time curl --get "http://localhost:8000/personadb/status"

echo ""
echo "=== 1. 康是美的目標客戶 ===（藥妝零售語意 — 不應套 aesthetic_procedure, #36）"
time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=康是美的目標客戶" \
            --data-urlencode "top_k=3" \
              --data-urlencode "opMode=僅篩選" | tee /tmp/kangshimei.json

echo ""
echo "=== 2. TESLA的目標客戶 ==="
time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=TESLA的目標客戶" \
            --data-urlencode "top_k=3" \
              --data-urlencode "opMode=僅篩選" | tee /tmp/tesla.json

echo ""
echo "=== 3. 時尚服裝設計師的目標客戶 ==="
time curl --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=時尚服裝設計師的目標客戶" \
            --data-urlencode "top_k=10" \
              --data-urlencode "opMode=僅篩選" | jq > fashion_closing.json


echo ""
echo "=== 4. 房貸優惠 — 房仲業者 ==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=房貸優惠方案" \
          --data-urlencode "role=房仲業者" \
          --data-urlencode "top_k=5" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/role_fangzhong.json

echo ""
echo "=== 5. 房貸優惠 — 銀行業者 ==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=房貸優惠方案" \
          --data-urlencode "role=銀行業者" \
          --data-urlencode "top_k=5" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/role_banker.json

echo ""
echo "=== 6. 醫美診所的目標客戶（dimension 20: aesthetic_procedure）==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=醫美診所的目標客戶" \
          --data-urlencode "role=醫美診所行銷主管" \
          --data-urlencode "top_k=10" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/aesthetic_closing.json

echo ""
echo "=== 7. 債務整合的目標客戶（dimension 21: debt_status）==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=債務整合貸款方案的目標客戶" \
          --data-urlencode "role=銀行債務整合專員" \
          --data-urlencode "top_k=10" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/debt_closing.json

echo ""
echo "=== 8. 小吃攤老闆的目標客群 — 【顧客語意】不應套 employment_status ==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=小吃攤老闆的目標客群" \
          --data-urlencode "role=夜市商圈協會" \
          --data-urlencode "top_k=10" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/boss_closing.json

echo ""
echo "=== 9. 業主本人 — dimension 22: employment_status（語意無歧義，issue #34）==="
time curl -s --get "http://localhost:8000/personadb/candidates" \
          --data-urlencode "questions=想找企業主或工廠老闆本人作為B2B問卷受訪者" \
          --data-urlencode "top_k=10" \
          --data-urlencode "opMode=僅篩選" | tee /tmp/owner_closing.json

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
               "llm_empty", "llm_parse_error", "llm_no_filters", "no_filters"}
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
    # 連續 no_op 上限 ≤ 2
    streak = mx = 0
    for b in ba:
        streak = streak + 1 if b.get("no_op") else 0
        mx = max(mx, streak)
    ok_streak = mx <= 2
    # 一致性：no_op_limit ⇒ 最後兩輪皆 no_op；target_reached ⇒ matched ≥ 20
    consistent = True
    if sr == "no_op_limit":
        consistent = len(ba) >= 2 and ba[-1].get("no_op") and ba[-2].get("no_op")
    elif sr == "target_reached":
        consistent = (cd.get("total_matched") or 0) >= 20
    print(f"  #56 {cname}: stop_reason={sr!r} loops={len(ba)} 連續空轉max={mx} → "
          + ("✅" if (ok_sr and ok_streak and consistent) else f"❌ (合法={ok_sr} 空轉={ok_streak} 一致={consistent})"))
_sr_seen = sorted({cd.get("broadening_stop_reason") for cd in _cases.values()})
print(f"  #56 本輪出現的停止原因: {_sr_seen}")
PYEOF

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
