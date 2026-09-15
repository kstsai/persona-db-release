# round11 — Persona DB v5.11.1 / NODE-A / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.2.0**）。
**本輪不做跨版本比對** —— 只分析 v5.11.1 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 執行時間：主套件 2026-09-15 **11:47:19Z → 12:10:45Z**；探針 **12:11:13Z → 12:4x**；追加探針（case08）**12:49:32Z →**
- 結果總覽：主套件 **10/10 HTTP 200**、斷言 **44 ✅ / 1 ⚠️ / 0 ❌ / 0 N/A**；探針 **13/13 HTTP 200**

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/<case>.body` | **逐位元組**回應 body（9 案例 + `00_status.body` + `openapi.json`） |
| `headers/` `meta/` `json/` | headers、量測欄位與實際 curl 指令、body 副本 |
| `meta/original-upstream-f3cb96ad.sh` | **原版腳本逐字留存**（sha256 `f3cb96ad…`，421 行） |
| `run-test.sh` | 本輪 runner（sha256 `ef6c0f36786937db…`，417 行；**執行前即記錄**） |
| `meta/script-provenance.txt` | 環境、部署保真度、儀器 sha、忠實度證明、跨輪防護 |
| `meta/make-runner.py` | 由原版機械組出 runner；**`OUT` 自我定位**（`dirname $0`） |
| `meta/verify-instrument.py` | 儀器忠實度證明（可指定要比對的 runner 檔） |
| `meta/test-runner-harness.sh` | runner/probe **執行時行為**單元測試（stub `curl`、11 項） |
| `extra/assertions.txt` | 斷言輸出（44 ✅ / 1 ⚠️） |
| `extra/server-log-window.txt` | 主套件窗口的**伺服器端** log |
| `probe/` | §6.8 重現性（06/07/08 各 3 次）+ §6.9 定向（t1–t4）+ `run-probe.sh` / `run-probe-08.sh` |
| `analyze.py` / `verify-extended.py`（A–U）/ `make-summaries.py` | 分析與檢查腳本 |
| `summary-*.csv` / `summary-all-cases.json` | 表格化摘要 |

### 探針題目原文（供查核）

`t1`／`t2`（第 10、11 輪另有 `t1`–`t4`）使用的是**刻意設計為「超出 schema、必然不可滿足」**的查詢：

```
questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主
```

Persona DB 的 24 個欄位沒有「遊艇」也沒有「私人飛機」，所以這題會逼 LLM 只能：
① 用最接近的財富代理指標（`income`／`family_income`／`clothing_spend`／`commute_mode`）硬套 → 命中極少或 0 筆；
② 產不出任何 filter。目的是**逼出主套件碰不到的分支**（`matched=0`、`pool_exhausted=true`、隨之而來的停止原因）。

> ⚠️ **這是探針，不是業務案例，也不是產品缺陷主張。** 在 `ps`／log／`summary` 看到這道題時請以此為準。
> 自第九輪起**同一題重複作為回歸哨兵**。**限制**：人造查詢驗的是分支機制，不是真實流量。

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

### 3. §6.1–§6.6 回應分析（含 protected_dims / veto / widened_dims）
```bash
python3 analyze.py
```

### 4. 延伸自證檢查（A–U；含 upstream 未驗的 G/H、K/L/M、S/T/U）
```bash
python3 verify-extended.py
```

### 5. §6.8 重現性：case08 的雙峰（本輪最重要的量測）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
print("case08（小吃攤老闆的目標客群 = 顧客語意）主套件 + 3 次重跑：")
for tag, p in [("主套件","raw/08_boss.body")] + [(f"探針 r{i}", f"probe/r08_boss_{i}.body") for i in (1,2,3)]:
    d = L(p); emp = (d["applied_filters"] or {}).get("employment_status")
    print(f"  {tag:8s} matched={d['total_matched']:3d} employment_status={emp} "
          f"→ {'❌ 反轉（業主）' if emp else '✅ 正確（顧客）'}")
PY
```

### 6. §6.8 重現性：case06 / case07
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for base, probe in (("raw/06_aesthetic.body","r06_aesthetic"), ("raw/07_debt.body","r07_debt")):
    print(f"— {probe} —")
    for tag, p in [("主套件", base)] + [(f"r{i}", f"probe/{probe}_{i}.body") for i in (1,2,3)]:
        d = L(p)
        print(f"  {tag:8s} matched={d['total_matched']:3d} protected={d['protected_dims']} "
              f"relaxed={d['relaxed_dims']} stop={d['broadening_stop_reason']!r}")
PY
```

### 7. §6.9 定向探針（含兩個 veto 事件）
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for t in ("t1_narrow_topk10","t2_narrow_topk100","t3_tesla_topk20","t4_banker_topk20"):
    d = L(f"probe/{t}.body")
    print(f"{t:20s} matched={d['total_matched']:3d} status={d['status']!r} "
          f"pe={d['pool_exhausted']} stop={d['broadening_stop_reason']!r}")
    for b in d["broadening_attempts"]:
        if b.get("protected_veto"):
            print(f"    ⛔ veto loop{b['loop']}: vetoed={b['vetoed_dims']} no_op={b['no_op']} "
                  f"changed={b['filters_changed']} {b['match_count_before']}→{b['match_count_after']}")
PY
```

### 8. 08↔09 名單重疊（語意反轉的指紋）
```bash
python3 - <<'PY'
import json, pathlib
def ids(p): return {x["id"] for x in json.loads(pathlib.Path(p).read_text(encoding="utf-8"))["summary"]}
b, o = ids("raw/08_boss.body"), ids("raw/09_owner.body")
print(f"08（小吃攤顧客）∩ 09（業主本人） = {len(b & o)}/10 = {len(b&o)/10*100:.0f}%")
print(sorted(b & o))
PY
```

### 9. 伺服器端交叉核對
```bash
grep -E 'HTTP/1.1' extra/server-log-window.txt | grep -v health
grep -c "Protected dims" extra/server-log-window.txt
grep -icE "retry|Traceback|Exception|ERROR|WARNING" extra/server-log-window.txt
```

---

## 一句話總結

**v5.11.1 把第十輪的三條建議都落地了，而且本輪逐項驗證有效**：值集放寬有了留痕欄位 `widened_dims`（3 輪有痕跡）、
空值清單有了守門（`#62` 斷言 + `_normalize_filters` 修復）、上游也把我的 K/L/M veto 不變式採納為出貨斷言；
核心維度保護在兩題各 4 次執行中 **8/8 成立**，定向探針還逼出**兩個真實 veto 事件**（模型要移除受保護維度 → 系統還原該輪）。

**但本輪最需要注意的是一條新的、更難防的問題**：「小吃攤老闆的目標客群（顧客語意）」這一題
**會隨機落到兩種相反的詮釋** —— 4 次執行中 **2 次把「顧客」當成「業主本人」**，
反轉時回傳的是高收入製造／服務業雇主，與 B2B 業主名單**重疊 9/10**；
而**兩個模式都回 `status='ok'`**，回應本身不會警示。這不是穩定缺陷，是**不可預測的判準漂移**。
