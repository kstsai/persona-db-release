# round12 — Persona DB v5.12 / NODE-A / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.4.0**）。
**本輪不做跨版本比對** —— 只分析 v5.12 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 執行時間：主套件 2026-09-15 **22:45:40Z → 22:56:40Z**（11 分 00 秒）；探針 **22:57:08Z → 23:1x**
- 結果總覽：主套件 **10/10 HTTP 200**、斷言 **53 ✅ / 0 ⚠️ / 0 ❌ / 1 ℹ️**；探針 **10/10 HTTP 200**

---

## 探針題目原文（供查核；skill v2.4.0 規定必須寫出原文）

`t1`／`t2` 使用的是**刻意設計為「超出 schema、必然不可滿足」**的查詢：

```
questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主
```

Persona DB 的 24 個欄位沒有「遊艇」也沒有「私人飛機」，所以這題必然逼出
`matched=0` / `pool_exhausted=true`（主套件碰不到的分支）。

> ⚠️ **這是探針，不是業務案例，也不是產品缺陷主張。** 在 `ps`／log／`summary` 看到這道題時請以此為準。
> 自第九輪起**同一題重複作為回歸哨兵**。**限制**：人造查詢驗的是分支機制，不是真實流量。

`r08`／`r06` 用的是主套件 case08／case06 的**完全相同參數**（`questions`／`role`／`top_k`／`opMode` 順序一致）。

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/` `headers/` `meta/` `json/` | 逐位元組 body、headers、量測欄位＋實際 curl 指令、body 副本 |
| `meta/original-upstream-2070ad91.sh` | **原版腳本逐字留存**（sha256 `2070ad91…`，480 行） |
| `run-test.sh` | 本輪 runner（sha256 `350e16a4253341c7…`，470 行；**執行前即記錄**） |
| `meta/script-provenance.txt` | 環境、部署保真度、儀器 sha、忠實度證明、跨輪防護 |
| `meta/make-runner.py` | 由原版機械組出 runner；**`OUT` 自我定位**（`dirname $0`） |
| `meta/verify-instrument.py` | 儀器忠實度證明（可指定要比對的 runner 檔） |
| `meta/test-runner-harness.sh` | runner/probe **執行時行為**單元測試（stub `curl`、11 項） |
| `extra/assertions.txt` | 斷言輸出（53 ✅ / 0 ⚠️ / 0 ❌） |
| `extra/server-log-window.txt` | 主套件窗口的**伺服器端** log（含 `Subject gate` 痕跡） |
| `probe/` | §6.8 重現性（case08／case06 各 3 次）+ §6.9 定向（t1–t4）+ `run-probe.sh` |
| `analyze.py` / `verify-extended.py`（A–X）/ `make-summaries.py` | 分析與檢查腳本 |

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

### 3. §6.1–§6.6 回應分析（含 subject / warnings / protected_dims / veto / widened_dims）
```bash
python3 analyze.py
```

### 4. 延伸自證檢查（A–X；含 upstream 未驗的 G/H、S/T 正確形式、V/X）
```bash
python3 verify-extended.py
```

### 5. §6.8 重現性：case08 的主體護欄（本輪最關鍵的量測）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
print("case08（小吃攤老闆的目標客群 = 顧客語意）主套件 + 3 次重跑：")
for tag, p in [("主套件","raw/08_boss.body")] + [(f"探針 r{i}", f"probe/r08_boss_{i}.body") for i in (1,2,3)]:
    d = L(p)
    print(f"  {tag:8s} subject={str(d.get('subject')):9s} matched={d['total_matched']:4d} "
          f"employment_status={(d['applied_filters'] or {}).get('employment_status')} "
          f"warnings={d.get('warnings')}")
PY
```

### 6. §6.8 重現性：case06
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for tag, p in [("主套件","raw/06_aesthetic.body")] + [(f"r{i}", f"probe/r06_aesthetic_{i}.body") for i in (1,2,3)]:
    d = L(p)
    print(f"  {tag:8s} matched={d['total_matched']:3d} protected={d['protected_dims']} "
          f"relaxed={d['relaxed_dims']} stop={d['broadening_stop_reason']!r}")
PY
```

### 7. §6.9 定向探針（含兩次 veto）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for t in ("t1_narrow_topk10","t2_narrow_topk100","t3_tesla_topk20","t4_banker_topk20"):
    d = L(f"probe/{t}.body")
    print(f"{t:20s} matched={d['total_matched']:3d} status={d['status']!r} subject={d.get('subject')!r} "
          f"pe={d['pool_exhausted']} stop={d['broadening_stop_reason']!r}")
    for b in d["broadening_attempts"]:
        if b.get("protected_veto"):
            print(f"    ⛔ veto loop{b['loop']}: vetoed={b['vetoed_dims']} "
                  f"{b['match_count_before']}→{b['match_count_after']}")
PY
```

### 8. 嚴格 S/T 是否會誤報（本輪的斷言設計問題）
```bash
python3 - <<'PY'
import json, pathlib
print("逐一重算『嚴格形式』（widened ⊆ applied、widened ∩ relaxed = ∅）：")
for p in sorted(list(pathlib.Path("raw").glob("0[1-9]*.body")) + list(pathlib.Path("probe").glob("*.body"))):
    try: d = json.loads(p.read_text(encoding="utf-8"))
    except Exception: continue
    if "total_matched" not in d: continue
    a = set(d["applied_filters"] or {}); r = set(d.get("relaxed_dims") or [])
    w = set(x for b in (d.get("broadening_attempts") or []) for x in (b.get("widened_dims") or []))
    if (w - a) or (w & r):
        print(f"  ❌ {p.parent.name}/{p.stem}: 嚴格S違反={sorted(w-a)} 嚴格T違反={sorted(w&r)}"
              f"（正確形式 S'={sorted(w-(a|r)) or '通過'}）")
PY
```

### 9. 伺服器端交叉核對（含 #65 主體護欄痕跡）
```bash
grep "Subject gate" extra/server-log-window.txt
grep -c "Protected dims" extra/server-log-window.txt
grep -c "剝除禁用維度" extra/server-log-window.txt      # 0 ⇒ warnings 路徑未被行使
grep -icE "retry|Traceback|Exception|ERROR|WARNING" extra/server-log-window.txt
```

---

## 一句話總結

**v5.12 的 `#65` 主體護欄真的把第十一輪的雙峰問題收斂了**：小吃攤（顧客語意）在主套件 + 3 次重跑
**4/4 都判為 `subject='customer'`**、`employment_status` 4/4 未被套用，名單回到中低消費力消費者；
同質化矩陣顯示**沒有任何 ≥8/10 的配對**（第十一輪是 9/10）。護欄也可稽核（伺服器端有 `Subject gate` log）。

**但要注意三件事**：① `#65` 的**剝除與 `warnings` 路徑本輪完全沒被行使**（19 筆全空、剝除 0 次）
—— 那條路徑目前是「宣告了但沒走過」；② 本輪被採納的 **S/T 不變式用的是過嚴的形式**，
會對合法的「先放寬值集、後整維移除」序列假警報（本輪 `05_role_banker` 就是新實例），
而它沒報錯只是因為**只掃 4/9 案例**；③ `subject` 只判定出 2/9 題，其餘題目不設限，
且**護欄固定的是詮釋、不是抽樣**（同一題 `matched` 仍在 45↔153 之間變動）。
