# round10 — Persona DB v5.10 / NODE-A / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.1.0**）。
**本輪不做跨版本比對** —— 只分析 v5.10 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 已知缺陷：**[meta/known-defects.txt](meta/known-defects.txt)** ← **讀證據前先讀這個**（本輪有一次證據寫錯目錄的疏失）
- 執行時間：主套件 2026-09-15 **03:34:16Z → 03:53:01Z**；探針 **03:56:02Z → 04:2x**
- 結果總覽：**10/10 HTTP 200**、斷言 **42 ✅ / 0 ⚠️ / 0 ❌ / 0 N/A**、探針 9/9 HTTP 200

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/<case>.body` | **逐位元組**回應 body（9 案例 + `00_status.body` + `openapi.json`） |
| `headers/<case>.headers` | 完整回應 headers |
| `meta/<case>.meta` | `http_code` / `time_total` / `size_download` / `url_effective` / 實際 curl 指令 |
| `json/<case>.json` | 同上 body 的副本 |
| `meta/original-upstream-f57392bb.sh` | **原版腳本逐字留存**（sha256 `f57392bb…`，372 行） |
| `run-test.sh` | 本輪 runner（sha256 `985fdb8198c08500…`，368 行；**執行前即記錄**） |
| `meta/aborted-attempt-runner-efa7f666.sh` | 第一次（中止）啟動用的 runner —— 保留以證明它寫死了 `qa-round9`（見 known-defects 缺陷 1） |
| `meta/script-provenance.txt` | 環境、部署保真度、儀器 sha、忠實度證明 |
| `meta/known-defects.txt` | **本包證據的已知缺陷**（3 項） |
| `meta/make-runner.py` | 由原版**機械組出** runner；`OUT` 由目錄名推導（修正後） |
| `meta/verify-instrument.py` | 儀器忠實度證明（可指定要比對的 runner 檔） |
| `meta/test-runner-harness.sh` | runner/probe **執行時行為**的單元測試（stub `curl`、不連網、11 項） |
| `extra/assertions.txt` | 斷言輸出（自 `run.log` 擷取，42 ✅） |
| `extra/server-log-window.txt` | 主套件窗口的**伺服器端** log（歸因用） |
| `probe/` | §6.8 重現性探針（3+3）+ §6.9 定向探針（3）+ `run-probe.sh` + `probe.log` |
| `analyze.py` / `verify-extended.py` / `make-summaries.py` | 分析與檢查腳本 |
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

### 3. §6.1–§6.6 回應分析（含 protected_dims / veto）

```bash
python3 analyze.py
```

### 4. 延伸自證檢查（A–P；含 upstream 未驗的 K/L/M/G/H）

```bash
python3 verify-extended.py
```

### 5. §6.8 重現性 與 §6.9 定向探針

```bash
python3 - <<'PY'
import json, pathlib
def load(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for tag, p in [("主套件 raw/06", "raw/06_aesthetic.body"), ("探針 r06_1", "probe/r06_aesthetic_1.body"),
               ("探針 r06_2", "probe/r06_aesthetic_2.body"), ("探針 r06_3", "probe/r06_aesthetic_3.body")]:
    d = load(p); print(f"{tag:16s} matched={d['total_matched']:3d} stop={d['broadening_stop_reason']:14s} "
                       f"protected={d['protected_dims']} relaxed={d['relaxed_dims']}")
print()
for t in ("t1_narrow_topk10", "t2_narrow_topk100", "t3_tesla_topk20"):
    d = load(f"probe/{t}.body")
    print(f"{t:20s} matched={d['total_matched']:3d} status={d['status']!r} stop={d['broadening_stop_reason']!r}")
    for b in d["broadening_attempts"]:
        if b.get("protected_veto"):
            print(f"    ⛔ veto loop{b['loop']}: vetoed={b['vetoed_dims']} no_op={b['no_op']} "
                  f"changed={b['filters_changed']} {b['match_count_before']}→{b['match_count_after']}")
PY
```

### 6. `#58` status 語意（逐筆，主套件 + 探針）

```bash
python3 - <<'PY'
import json, pathlib
for p in sorted(list(pathlib.Path("raw").glob("0[1-9]*.body")) + list(pathlib.Path("probe").glob("*.body"))):
    d = json.loads(p.read_text(encoding="utf-8"))
    if "total_matched" not in d: continue
    tm, st = d["total_matched"], d.get("status")
    print(f"{'✅' if (tm == 0) == (st != 'ok') else '❌'} {p.stem:22s} matched={tm:3d} status={st!r}")
PY
```

### 7. 單一案例的人工複驗（案例 07 債務整合）

```bash
python3 -c "import json;d=json.load(open('raw/07_debt.body',encoding='utf-8'));print('applied:',d['applied_filters']);print('protected:',d['protected_dims']);print('relaxed:',d['relaxed_dims']);print('stop:',d['broadening_stop_reason'])"
```

### 8. 伺服器端交叉核對（歸因紀律）

```bash
grep -E 'HTTP/1.1' extra/server-log-window.txt | grep -v health
grep -c "Protected dims" extra/server-log-window.txt     # #60 的 INFO 診斷
grep -icE "retry|Traceback|Exception|ERROR|WARNING" extra/server-log-window.txt
```

---

## 一句話總結

**v5.9/v5.10 針對第九輪指出的三個問題（核心維度被放寬、`status` 語意、`no_op` 語意）都做了機制化的修正，
而本輪以回應逐項驗證它們確實有效**：`protected ∩ relaxed = ∅` 在兩題各 4 次執行中全數成立、
`matched==0 ⇔ status!='ok'` 在 18/18 筆成立、10 輪放寬 **0 空轉 0 overshoot**、
自述與實作 **0 矛盾**，且定向探針逼出了主套件沒涵蓋的**硬性 veto**（模型試圖移除受保護維度 → 系統還原該輪並停止）。
**仍要注意**：同一 query 的 `matched` 變異極大（案例 07 為 **0 ↔ 30**）；
「值集放寬」（`sex` 由女放寬為女+男）**不留痕也不受任何護欄**；
`applied_filters` 可出現**空值清單**（源碼證明等同排除所有人）；`broadening_stop_reason` 仍有 2 個不可達的值。
