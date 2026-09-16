# round14 — Persona DB v5.14 / NODE-A / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.6.0**）。
**本輪不做跨版本比對** —— 只分析 v5.14 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 執行時間：主套件 2026-09-16 **02:43:14Z → 03:16:21Z**（33 分 07 秒）；探針 **03:38:15Z → 04:05:56Z**
- 結果總覽：主套件 **10/10 HTTP 200**、斷言 **60 ✅ / 0 ⚠️ / 0 ❌ / 0 ℹ️**；探針 **10/10 HTTP 200**

---

## 探針題目原文（供查核；skill v2.4.0 規定必須寫出原文）

| 探針 | 題目原文 | 為什麼要這樣設計 | 本輪結果 |
|:--|:--|:--|:--|
| **`t1`** | `questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主` | **超出 schema、必然不可滿足**：24 個欄位沒有「遊艇」／「私人飛機」⇒ 逼出 `matched=0`／`pool_exhausted=true`。自第九輪起的**回歸哨兵** | ✅ `matched=0`、`too_strict`、`pe=True` |
| **`t2`** | `questions=時尚服裝設計師的目標客戶`（`top_k=10`，= 主套件 case03 原參數） | **逼出 `overshoot_restore`（#70 A）**：需要某輪放寬後樣本數 **> 40**。第十三輪的 case03 正是在這裡 `18→105`（5.8×） | ❌ **未達標**：本輪 `18→28`（模型主動避開 `hobby`）→ 分支未被行使 |
| **`t3`** | `questions=想找做過醫美療程的45歲單身女性` | **逼出 `protection_saturated`（#66 C）**：收窄到讓「已套用維度 ⊆ 保護集」成立（第十三輪曾成功） | ❌ **未達標**：本輪保護集只 1 個維度 → 不飽和 |
| `t4` | `questions=TESLA的目標客戶`（`top_k=20`） | #61 `commute_mode` 保護的回歸 | ✅ `commute_mode` 受保護未放寬 |

> ⚠️ **這些都是刻意設計的探針，不是業務案例，也不是產品缺陷主張**（「夜市小吃攤的老闆不會真的想找擁有遊艇的人」）。
> **限制**：人造查詢驗的是**分支機制**，不是真實流量。
> `r08`／`r06` 用的是主套件 case08／case06 的**完全相同參數**（`questions`／`role`／`top_k`／`opMode` 順序一致）。

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/` `headers/` `meta/` `json/` | 逐位元組 body、headers、量測欄位＋實際 curl 指令、body 副本 |
| `meta/original-upstream-fb2c2fda.sh` | **原版腳本逐字留存**（sha256 `fb2c2fda…`，579 行） |
| `run-test.sh` | 本輪 runner（sha256 `2bbcbb1bf07175e3…`，569 行；**執行前即記錄**） |
| `meta/script-provenance.txt` | 環境、部署保真度、儀器 sha、忠實度證明、跨輪防護 |
| `meta/make-runner.py` / `meta/verify-instrument.py` / `meta/test-runner-harness.sh` | runner 產生器（`OUT` 自我定位）、忠實度證明、執行時行為單元測試（11 項） |
| `extra/assertions.txt` | 斷言輸出（60 ✅） |
| `extra/server-log-window.txt` | 主套件窗口的伺服器端 log |
| `probe/` | §6.8 重現性（case08／case06 各 3 次）+ §6.9 定向（t1–t4）+ `run-probe.sh` |
| `analyze.py` / `verify-extended.py`（A–AF）/ `make-summaries.py` | 分析與檢查腳本 |

---

## 複驗指令（每一條都已實跑過）

### 1. 儀器忠實度
```bash
python3 meta/verify-instrument.py
```

### 2. runner/probe 的執行時行為（不連網）
```bash
bash meta/test-runner-harness.sh
```

### 3. §6.1–§6.6 回應分析
```bash
python3 analyze.py
```

### 4. 延伸自證檢查（A–AF；含由契約推導的來源鍵檢查）
```bash
python3 verify-extended.py
```

### 5. §6.8 重現性：case08 主體護欄（4/4 一致）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for tag, p in [("主套件","raw/08_boss.body")] + [(f"探針 r{i}", f"probe/r08_boss_{i}.body") for i in (1,2,3)]:
    d = L(p)
    print(f"  {tag:8s} subject={str(d.get('subject')):9s} matched={d['total_matched']:4d} "
          f"emp={(d['applied_filters'] or {}).get('employment_status')}")
    print(f"  {'':8s} basis={d.get('subject_basis')!r}")
PY
```

### 6. §6.9 定向探針：t2/t3 **未達標**（本輪最重要的誠實聲明）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for t, want in (("t1_narrow_topk10","matched=0/pool_exhausted"),
                ("t2_fashion_overshoot","overshoot_restore(#70 A)"),
                ("t3_aesthetic_narrow","protection_saturated(#66 C)"),
                ("t4_tesla_topk20","#61 commute_mode")):
    d = L(f"probe/{t}.body")
    af, pd_ = set(d["applied_filters"] or {}), set(d["protected_dims"] or {})
    print(f"  {t:22s} matched={d['total_matched']:3d} stop={d['broadening_stop_reason']!r:22s} 目標={want}")
    print(f"  {'':22s} applied⊆protected? {af <= pd_}   overshoot={[b.get('overshoot') for b in d['broadening_attempts']]}"
          f"   restore={[b.get('overshoot_restore') for b in d['broadening_attempts']]}")
PY
```

### 7. `#69` 值集放寬幅度（`widened_deltas`）
```bash
python3 - <<'PY'
import json, pathlib
for c in ("06_aesthetic","07_debt","04_role_fangzhong"):
    d = json.loads(pathlib.Path(f"raw/{c}.body").read_text(encoding="utf-8"))
    for b in d["broadening_attempts"]:
        for x in (b.get("widened_deltas") or []):
            print(f"  {c} loop{b['loop']} {x['dim']}: {x['before']} → {x['after']}  added={x['added']}")
PY
```

### 8. `#71 B` 上限（可在部署層稽核）
```bash
python3 -c "
import json,pathlib
for c in ['01_kangshimei','03_fashion','07_debt','09_owner']:
    d=json.loads(pathlib.Path(f'raw/{c}.body').read_text(encoding='utf-8'))
    md=(d.get('protected_dims_sources') or {}).get('model_declared') or []
    print(f\"  {c:20s} cap={d.get('declared_protected_cap')}  len(model_declared)={len(md)}\")
"
```

### 9. `llm_parse_error` 的靜默性（本輪新發現）
```bash
grep -n "llm_parse_error" extra/assertions.txt
python3 -c "
import json,pathlib
d=json.loads(pathlib.Path('raw/02_tesla.body').read_text(encoding='utf-8'))
print(f\"  case02 stop={d['broadening_stop_reason']!r} matched={d['total_matched']} loops={len(d['broadening_attempts'])} warnings={d.get('warnings')}\")
"
# 伺服器端完全沒有痕跡（該 except 分支不寫 log）：
grep -icE "parse|解析失敗|finish_reason" extra/server-log-window.txt
```

### 10. 伺服器端交叉核對
```bash
# 關鍵事件（全窗口 = 主套件 + 10 個探針）
for pat in overshoot 受保護維度被變更 已還原該輪 protection_saturated 已達上限; do
  printf "  %-22s %s\n" "$pat" "$(grep -c "$pat" extra/server-log-window.txt)"
done
printf "  %-22s %s\n" "Traceback/Exception/ERROR" "$(grep -cE 'Traceback|Exception|ERROR' extra/server-log-window.txt)"
# 有時間戳的事件行（access log 不帶時間戳，故不能按時間切窗口）
printf "  %-22s %s\n" "Protected dims" "$(grep -c 'Protected dims' extra/server-log-window.txt)"
printf "  %-22s %s\n" "Subject gate" "$(grep -c 'Subject gate' extra/server-log-window.txt)"
```

---

## 一句話總結

**v5.14 把第十三輪的兩個教訓完全落實**：所有案例級不變式**統一掃 9/9 並印出掃描數**，
而且**空轉的 ✅ 會主動標示**（`#57 veto 事件數（掃描 9/9）= 0 → 空轉（K/L/M 不具檢定效力）`）。
新增的三個可稽核欄位裡**兩個已驗證有效**：`widened_deltas` 給出放寬幅度（8 輪有痕跡）、
`declared_protected_cap` 讓上限可在部署層稽核；S' 的正確形式也在真實資料上得到驗證
（案例 04 的「先放寬 `age`、後移除 `age`」被**正確列為資訊性**而非假 ❌）。

**但本輪最重要的是一個誠實的「未達標」**：我為 `overshoot_restore`（#70 A）設計的定向探針
**沒能觸發它**（模型主動避開 `hobby`，只做到 `18→28`，未達 >40 門檻），
`protection_saturated` 本輪也未重現 ⇒ **這兩個分支本輪都沒有產生證據**，
其中 `overshoot_restore` **至今從未被驗證過**。另外首次觀測到 `llm_parse_error`
（分支會動），但它**在伺服器端完全不留 log**，無法統計頻率或判讀型態。
