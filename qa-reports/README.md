# LLM Verify QA Reports — persona-db API 跨版本實測

> **同一份測試腳本**（`upDockerVerHermes/test-persona-db-api.sh`）對**多個版本／節點**重複執行，
> 逐案例保存 **byte 級證據**，產出可交叉比對的跨版本報告。
>
> 方法論：`api-version-sweep` skill（dsh 系共用 kit）。
> 執行者：dsh1（DeepSeek Harness）。**五輪的 runner sha256 完全相同** ⇒ 跨輪可比。

---

## 五輪一覽

| # | 版本 | 節點 | 日期 | 契約 sha256(16) | 結果 | 該輪重點 |
|:-:|:-----|:-----|:-----|:----------------|:-----|:---------|
| 1 | **v4.9.2** | `lzcdh5` | 2026-09-12 | `8ac54b95228d85fc` | 9/9 200 | 基線。發現 `aesthetic_procedure`/`debt_status`/`employment_status` 三維度**不存在** |
| 2 | **v5.2** | `lzc-dh1-1` | 2026-09-12 | `8b869ae266992056` | 9/9 200 | **+3 維度**（25 維）並投入運作；但樣本變異達 **62×**、空轉率 41% |
| 3 | **v5.3.1** | `lzcdh5` | 2026-09-12 | `8b869ae266992056` | 9/9 200 | 純行為 patch（契約同 v5.2）。`dims_counted` 修正為 0 不一致；變異收斂到 1.3× |
| 4 | **v5.4** | `lzc-dh1-1` | 2026-09-12 | `30a228782154bdce` | **8/9**（1×503） | 新增 `pool_exhausted`/`returned`/`no_op`/`overshoot`/`score_scale`；首見 503 且**該錯誤回應違反自身宣告 schema** |
| 5 | **v5.6** | `lzc-dh1-1` | 2026-09-13 | `aafe647f46ee8abe` | 9/9 200 | **契約型別化**（`BroadeningAttempt`/`ScoringBasis`，落實第 4 輪建議）；延遲 **98.2s 全系列最快** |

**共 4 種不同契約**（v5.2 與 v5.3.1 同 hash ⇒ 純行為 patch）。

---

## 目錄（**刻意沿用原始目錄名**）

```
qa-reports/
├── README.md                          ← 本檔（索引）
├── personadb-lzcdh5-api-verify/       ← 第 1 輪 v4.9.2
├── personadb-dh1-api-verify/          ← 第 2 輪 v5.2
├── personadb-lzcdh5-v531-api-verify/  ← 第 3 輪 v5.3.1
├── personadb-dh1-v54-api-verify/      ← 第 4 輪 v5.4
└── personadb-dh1-v56-api-verify/      ← 第 5 輪 v5.6
```

> **為何不改成 `v5.6-lzc-dh1-1/` 這種更好讀的名字？**
> 因為每包的 `README.md` 複驗指令與 `compare-nway.py` 都以**原始目錄名**互相引用
> （例如「v5.4 vs v5.6」的對照指令寫死了 `../personadb-dh1-v54-api-verify`）。
> **改名會讓那些已驗證過的指令全部失效** —— 違反本方法論「README 每條指令都要實跑過」的紀律。
> 版本對照請看上面的表。

---

## 每包的內容

| 檔案／目錄 | 內容 |
|:---|:---|
| `ANALYSIS.md` | **主報告**：逐案例分析 + 跨版本對照 + 發現（每條標嚴重度與「證據/觀察/空轉」級別） |
| `README.md` | 證據地圖 + **可執行複驗指令**（每條都經實跑、輸出與文件一致） |
| `run-test.sh` | 實際執行的 runner（五輪 sha256 相同） |
| `run.log` | 完整執行 stdout（含每案例 echo 標籤與完整 response body） |
| `raw/` | **逐位元組** response body（+ `openapi.json` 契約） |
| `headers/` | 每案例完整 HTTP response headers |
| `meta/` | http_code / 耗時 / bytes / **curl 參數** / 節點 provenance |
| `json/` | `raw/` 的 pretty-print 版 |
| `repeat/` | 重現性探針（同查詢 N≥3 次；逾時也是證據） |
| `probe/` | 定向探針（驗證新欄位語意、端點異常診斷） |
| `supplemental/` | `/personadb/detail` 樣本（維度字典查證） |
| `summary-per-case.csv` | 逐案例彙總（Excel 可開） |
| `summary-per-persona.csv` | 逐 persona 明細 |
| `version-comparison-nway.csv` | 跨版本對照表 |

---

## 怎麼複驗

### 最短路徑：讀主報告

```bash
less qa-reports/personadb-dh1-v56-api-verify/ANALYSIS.md
```

### 抽驗原始證據（不重跑，零成本）

```bash
cd qa-reports/personadb-dh1-v56-api-verify
cat raw/07_debt.body | jq .        # 位元組級證據
cat meta/07_debt.meta              # HTTP code / 耗時 / curl 參數
cat headers/07_debt.headers
```

### 五版交叉對照（不需重跑，用已保存的證據）

```bash
cd qa-reports/personadb-dh1-v56-api-verify
python3 compare-nway.py \
  ../personadb-lzcdh5-api-verify \
  ../personadb-dh1-api-verify \
  ../personadb-lzcdh5-v531-api-verify \
  ../personadb-dh1-v54-api-verify \
  ../personadb-dh1-v56-api-verify
# 註：會在最後一個目錄寫出 version-comparison-nway.csv
```

### 各包自己的複驗指令

每包 `README.md` 內有 10+ 條可執行指令（契約一致性、不變式、探針、跨版本指標等），
**全部經實跑驗證、輸出與文件一致**。

### 重跑整套（⚠️ 需連得到受測節點，約 13–30 分鐘／輪）

```bash
cd qa-reports/personadb-dh1-v56-api-verify
OUT=/tmp/rerun BASE_URL=http://<node>:8000 bash run-test.sh
```

> ⚠️ **重跑結果必然不同** —— endpoint 為 LLM-backed，實測同一查詢 `total_matched` 變異可達 **62×**。
> 保留本目錄作 baseline 才能做「同查詢不同結果」比對。

---

## 跨輪重要發現（完整版見各包 ANALYSIS.md）

### 已修正 ✅
- **v5.2**：新增並實際使用 `aesthetic_procedure` / `debt_status`（第 1 輪報告指出它們不存在）
- **v5.3.1**：`scoring_basis.dims_counted` 低報計分維度 → **不一致數 33 → 11 → 0**
- **v5.4**：新增 `pool_exhausted` / `returned`（回應第 3 輪「回傳數 < top_k 是契約風險」）、`score_scale: "relative-within-version"`（回應第 3 輪「分數不可跨版本比較」）
- **v5.6**：`BroadeningAttempt` / `ScoringBasis` **型別化** —— 直接落實第 4 輪「新欄位只寫在描述裡、codegen 看不到」的建議
- **v5.6**：延遲降至 **98.2s**（前四輪 144–204s）；收入桶完全飽和案例降到 **2/8**（第 1 輪為 7/8）

### 仍未解 ⚠️
- **`employment_status` 連續五輪從未被套用（0/8）** —— 含案例 08，其標籤明載測試該維度
- **ranking 層不可重現**：版本內 top-3 交集多為 0–1/3（filter 層在 v5.3.1 後趨穩，但未傳導到最終選擇）
- **分數尺度跨版本漂移**（案例 04：v5.4 `4.86` → v5.6 `2.54`）⇒ 有絕對分數門檻的下游邏輯升級會失效

### 值得注意的事件
- **v5.4**：HTTP 503 `FILTER_FAILED`，且**該回應違反自身宣告的 `ErrorResponse` schema**（宣告 required `error`，實際只回 `detail`）
- **v5.6**：重現性探針首次執行 **3/3 於精確 75.00s 硬切、完全無 HTTP 回應**（`http=000`）→ transient，約 10 分鐘後恢復。對照 v5.4 的結構化 503，**疑似錯誤處理退步**（未證實同因）
- **v5.6**：`opMode` **預設值由「兩者皆可」改為「僅篩選」** —— 對未明傳該參數的呼叫者是 breaking change

---

## 儀器忠實度

- 上游腳本 sha256：`33749d4e5218f3860f15f4296c5fc5ea90f0fa93f441bc4eba9faf2274dad2e3`
- 改寫後 runner sha256：`ffc7b10642f72f4120a43b77848ed722c6cf865c23b3267a3eb87bd48c74695d`（**五輪相同**）
- 相對原腳本的改動**只有三項**（base URL、證據落盤、diff check 解析工具），
  **請求參數／順序／斷言邏輯 100% 未變**。詳見各包 `ANALYSIS.md` §8。

## 誠實聲明

- 除案例 01 有 3–4 次取樣，其餘案例每輪僅 **1 次**執行；**已知 LLM 雜訊大，單次差異不可歸因於版本**。
  各報告中已逐處標示該條屬「證據」「觀察」或「空轉」。
- 五輪橫跨兩台機器（`lzcdh5` 與 `lzc-dh1-1`，公網 IP 同為 `1.169.214.22`），
  **延遲比較受硬體／網路影響，只當參考**。
- 第 3 輪報告的「收入桶完全飽和案例數」初稿有計算錯誤（寫 5/8、4/8，實為 **7/8、5/8**），
  已於 2026-09-13 更正並在檔內註明。
