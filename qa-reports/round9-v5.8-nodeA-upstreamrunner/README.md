# round9 — Persona DB v5.8 / NODE-A / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.0.0**）。
**本輪不做跨版本比對** —— 只分析 v5.8 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 已知缺陷：**[meta/known-defects.txt](meta/known-defects.txt)** ← 讀證據前先讀這個
- 執行時間：2026-09-14 12:28:39Z → 12:46:10Z（主套件）；探針 12:57:04Z → 13:17:16Z
- 結果總覽：**10/10 HTTP 200**、斷言 **31 ✅ / 1 ⚠️ / 0 ❌ / 0 N/A**、`total_matched` 見 §2

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/<case>.body` | **逐位元組**回應 body（9 個候選案例 + `00_status.body` + `openapi.json`） |
| `headers/<case>.headers` | 完整回應 headers（含狀態碼、content-type） |
| `meta/<case>.meta` | `http_code` / `time_total` / `size_download` / `url_effective` / 實際 curl 指令 |
| `json/<case>.json` | 同上 body 的副本（方便 `jq`） |
| `meta/original-upstream-e6c6fe77.sh` | **原版腳本逐字留存**（sha256 `e6c6fe77…`，301 行） |
| `meta/script-provenance.txt` | 目標環境、部署保真度、儀器 sha、忠實度證明 |
| `meta/known-defects.txt` | 本包證據的已知缺陷與影響範圍 |
| `meta/make-runner.py` | 由原版**機械組出** runner（切片，不手抄） |
| `meta/verify-instrument.py` | 儀器忠實度證明（請求參數／斷言段逐字比對） |
| `meta/test-runner-harness.sh` | runner/probe 接線的單元測試（stub curl、不連網） |
| `run-test.sh` | 本輪 runner（修好 helper 後重建的版本，sha256 `6d3a97d2ca3da055…`） |
| `meta/run-test-as-executed.sh` | **實際產出本輪證據的 runner**（sha256 `1557c38eb85215c1…`，298 行） |
| `run.log` | 執行日誌（**案例標題印成 tmpname，見 known-defects.txt**） |
| `extra/assertions.txt` | 斷言輸出（自 `run.log` 擷取） |
| `extra/server-log-window.txt` | 主套件窗口的**伺服器端** log（歸因用） |
| `extra/server-log-probe-window.txt` | 探針窗口的伺服器端 log |
| `probe/` | §6.8 重現性探針（3+3 次）+ §6.9 定向探針（3 個）+ `run-probe.sh` + `probe.log` |
| `analyze.py` / `verify-extended.py` / `analyze-probes.py` | 分析與檢查腳本 |
| `make-summaries.py` → `summary-*.csv` / `summary-all-cases.json` | 表格化摘要 |

---

## 複驗指令（每一條都已實跑過，輸出如下）

### 1. 儀器忠實度 —— 「不可改的沒被改」

```bash
python3 meta/verify-instrument.py meta/run-test-as-executed.sh   # 實際執行的那一份
python3 meta/verify-instrument.py                                # 修好 helper 後的本機版本
```
```text
[1] 請求參數／順序   upstream=32 runner=32  ✅ 相同
[2] 前段 L1-L14      ✅ 逐字相同
[3] 尾段（斷言）     upstream L88-L301=215 元素; runner 對應=215 元素  ✅ 逐字相同（0 差異）
[4] 案例標籤         upstream=9 runner=9  ✅ 逐案相同（含 #36 那條內含 === 的標籤）
[5] 差異總量         as-executed 143 行 / 本機版 142 行 —— 全部落在 upstream L15–L87（案例定義區）
結論：✅ 儀器忠實度成立 —— 請求參數與斷言邏輯零差異
```

> ⚠️ **本輪有兩份 runner，別搞混**（詳見 `meta/known-defects.txt` 缺陷 1 與 `meta/script-provenance.txt`）：
> **`meta/run-test-as-executed.sh`（`1557c38e…`，298 行）才是產出本輪證據的那一份**；
> 現行的 `run-test.sh`（`6d3a97d2…`，297 行）是修好 helper 之後重建的版本。
> 兩份的請求參數與斷言段都與 upstream 逐字相同，差異只在 helper 取參數的接線。

### 2. runner 接線單元測試（不連網、不呼叫 LLM）

```bash
bash meta/test-runner-harness.sh
```
```text
通過 11 項，失敗 0 項
```

### 3. §6.1–§6.5 回應分析

```bash
python3 analyze.py
```
輸出含：逐案例總表、`applied_filters` vs `reasoning`、自證性 15 項、計分誠實性配對、放寬逐輪、頭部集中。

### 4. 延伸自證檢查（upstream 沒驗的那些）

```bash
python3 verify-extended.py
```
```text
✅ 全部延伸自證檢查通過（旗標與數字一致、內外欄位無矛盾）
```
其中檢查 **G/H**（`no_op`／`overshoot` 旗標是否與 `match_count_before/after` 一致）是 upstream 完全沒做的。

### 5. §6.8 重現性 與 §6.9 定向探針

```bash
python3 analyze-probes.py
```
輸出含：兩題各 3 次的並列比較（**案例 06：4 次執行 4 種結果**）、三個定向探針的結果（含 503）。

### 6. 斷言結果

```bash
cat extra/assertions.txt
```
`31 ✅ / 1 ⚠️ / 0 ❌`；唯一 ⚠️ 是 `#42 debt_status 保留=False 符合率=8/10 (80%)`，成因判定見 `ANALYSIS.md` §3.1。

### 7. 單一案例的人工複驗（例：債務整合那一題）

```bash
# 這次請求實際打了什麼 URL
grep '^url_effective=' meta/07_debt.meta

# 套用／放寬了哪些維度、停止原因
python3 -c "import json;d=json.load(open('raw/07_debt.body',encoding='utf-8'));print('applied:',d['applied_filters']);print('relaxed:',d['relaxed_dims']);print('stop:',d['broadening_stop_reason'])"

# 逐輪放寬的自述（本輪最關鍵的一段引文）
python3 -c "import json;d=json.load(open('raw/07_debt.body',encoding='utf-8'));[print(f\"loop{b['loop']} {b['match_count_before']}→{b['match_count_after']}\n  {b['change']}\n\") for b in d['broadening_attempts']]"

# 回傳名單的 debt_status（★ 兩筆為「無」）
python3 -c "import json;d=json.load(open('raw/07_debt.body',encoding='utf-8'));[print(f\"{i:2d}. {r['id']} {r['name']} debt_status={r['debt_status']!r} score={r['score']}\") for i,r in enumerate(d['summary'],1)]"
```

### 8. 伺服器端交叉核對（歸因紀律）

```bash
grep -E 'HTTP/1.1' extra/server-log-window.txt | grep -v health
```
共 **13 行**非 health 請求：9 個 `200` 的 candidates、1 個刻意的 `400`（`#47` 負向測試）、
1 個 `/personadb/status`、2 個 `/openapi.json`。
`grep -icE "retry|finish_reason|Traceback|Exception|ERROR" extra/server-log-window.txt` → **0**
（本輪延遲不含救援重試）。

探針窗口則可見 503 的真因：
```bash
grep -v health extra/server-log-probe-window.txt | tail -3
# → LLM returned no filters, falling back to keyword parsing
# → "...questions=目標客戶..." 503 Service Unavailable
```

### 9. 重新產生摘要表

```bash
python3 make-summaries.py && head -3 summary-per-case.csv
```

---

## 一句話總結

**v5.8 在契約、可觀測性、計分誠實度上很乾淨（可自證性缺口 0、(b) 低報 0、斷言 31✅），
但「放寬步驟會把分析步驟認定為必要的維度移掉」是真實且可複驗的問題** —— 案例 07 的同案例
自我矛盾（loop1「不可放寬」→ loop2「移除」）造成 8→58 的失控放寬，並讓回傳名單尾部出現
「完全沒有債務」的人；**且案例 06／09 重跑結果不可重現**，任何單次判讀都只是一次抽樣。
