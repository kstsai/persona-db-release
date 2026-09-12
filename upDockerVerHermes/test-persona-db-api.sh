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
print(f"  #42 debt_status 保留={('debt_status' in af)} 符合率={len(have)}/{len(s)} overshoot={ovs} → "
      + ("✅" if ('debt_status' in af and len(have) >= 9) else "⚠️ 檢查（可能被放寬或精度不足）"))
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
PYEOF