# HANDOVER PROMPT — Persona DB 接手前文

> **用法**：開新 session 時，把本檔**整份**貼進你的 AI agent（或人工作業前讀一遍）。
> 它是**脈絡與紀律**，不是一次性指令；後面的「任務範本」才是具體工作。
> 本檔假設你的環境已有 `persona-db/`（交付包解開後的目錄）。

---

## 0. 你的角色

你是 **Persona DB 的接手團隊**（RD／QA／資料生產）。這個資料庫是**台灣人口加權的合成人設資料庫**
（現行 1069 位，可擴充），提供 HTTP API 讓使用者用自然語言找到目標族群的人設，並取出完整人設內容。

**你要能獨立完成三件事**：① 用新版規格／新資料集**重建或擴充**資料庫 ② **驗證**（含獨立複驗）
③ **出貨與部署**。原團隊不在此迴圈內 —— 所以**證據要自己產、結論要能被別人複驗**。

---

## 1. 環境與檔案地圖

| 位置 | 內容 | 權威性 |
|:--|:--|:--|
| `tw-persona-db-rfc.md` | **規格書**：維度設計、一致性規則、輸出格式、命名與隱私原則、scoring | **規格權威** |
| `concepts/` | 設計知識 14 篇（為何這樣設計、踩過的坑與根因） | **設計權威** |
| `sources/` | 原始統計資料（`jcic/*.csv` 等）；每個目錄有 `README.md` 說明來源 | **資料權威** |
| `tw_persona_1069.json` | 現行人設資料集 | 產物 |
| `dim_weights.json` | 相關性權重表（含 `weight_version`、資料年度） | 產物（由 `scripts/gen_dim_weights.py` 產生） |
| `scripts/` | 生產與驗證腳本（`gen_dim_weights.py`、`check_dim_weights.py`、`check_response_schema.py`、`contradiction_hunt/`、`test_*.py`） | 工具 |
| `api/` | 服務（`server.py`／`llm.py`／`models.py`／`persona_matcher.py`） | 產物 |
| `upDockerVerHermes/` | 部署與出貨驗證（`deploy-*.sh`、`test-persona-db-api.sh`、`RELEASE-VERSION`） | 工具 |
| `docs/handover/` | 本交接包（操作層） | 指引 |

**API 端點**：`/personadb/candidates`（產出人設名單）、`/personadb/detail`（取完整人設）、
`/personadb/status`、`/health`、`/docs`（Swagger UI）。操作細節見 `docs/swagger-quickstart.md`。

---

## 2. 五條鐵則（違反其一，成果不可信）

1. **證據紀律**：任何「我沒看到／我做不到」的結論前，**先驗你的量測方式**。
   工具給你的 0 可能是偽陰性（例：`docker logs` 遇到 log 檔的 NUL hole 只吐出 90/3103 行）。
   → 讀 log 一律**優先讀原始 log 檔**；用 `docker logs` 時要標明來源。
2. **斷言紀律**：驗證程式的斷言要 ① **掃描範圍＝全部案例**（並印出 `掃描 N/M`）
   ② **「沒事件」要明示空轉**（不具檢定效力），不可印 ✅ 假裝驗過
   ③ 檢查工具本身要**雙向驗證**（乾淨的要 0 命中、已知問題的要命中）。
3. **版本紀律**：任何 `api/*.py` 或資料變更 → **bump 版號**並重打包
   （純文件改動不 bump）。`VERSION`、`RELEASE-VERSION`、tag、tarball 名稱**四者必須一致**。
4. **資料紀律**：數字類結論一律標註**抽樣變異**（n=1069 的佔比誤差約 ±1–3 個百分點）；
   金額類外部統計**不要當個人所得用**（口徑不同）；來源要能回溯到 `sources/` 或標明出處。
5. **去識別化**：產物（tarball、報告）**不得**含憑證、內部主機名／IP、內部人員識別。
   出貨前跑掃描；**先修再 commit**（已 commit 的憑證會留在歷史）。

---

## 3. 兩個核心迴圈

### 迴圈 A — 資料生產（新增／修正人設）

```
讀規格（RFC §維度設計、§一致性規則、§輸出格式、§命名原則）
  → 盤點資料來源（sources/，或以新 dataset 取代／擴充）
  → 產生 dataset（每人設：dimensions + prompt_prefix + reference_pre_prompt）
  → 一致性驗證（佔比合理性、矛盾獵捕 contradiction_hunt）
  → 權重表（gen_dim_weights.py）→ 契約檢查（check_dim_weights.py / check_response_schema.py）
  → 抽樣人工／LLM 覆核 → 進版
```

**決策樹（最重要的一條）**：

| 情況 | 做法 | 理由 |
|:--|:--|:--|
| **新增維度**（如第 23 維） | **就地補註（in-place annotate）**：只對現有 dataset 逐筆補上該維度 | 保留既有已驗證的分布，成本低、可回溯 |
| **基礎維度模型修正**（如就業狀態定義改變） | **整批重建（full regen）**，完成後**重跑新維度的補註** | 基礎分布變了，補註的維度必須在新基礎上重算 |

### 迴圈 B — 驗證與出貨

```
出貨驗證套件（upDockerVerHermes/test-persona-db-api.sh）
  → 判讀結果（區分「產品缺陷」與「斷言/環境問題」；空轉要說空轉）
  → 有缺陷 → 開票（含修法＋驗證方式）→ 修 → 單元 → 真 LLM e2e → 出貨 SOP
  → 打包（去識別化＋守門掃描）→ 部署 → 版本一致性 → 0 紅旗
```

**判讀三個常犯的錯**（本資料庫歷史上反覆出現，請直接避開）：

1. **把「LLM 每次不同」當成 regression**：同一題連跑 3 次結果不同是**正常**；
   要判 regression 得固定指標、多次重跑、且看**機制性訊號**（欄位、護欄、不變式）而非單次數字。
2. **把「斷言的問題」當成產品缺陷**：斷言涵蓋不足／口徑不一致都會產生假警報
   （實例：斷言只掃 4/9 案例卻印「未觸發」；倍率在修正動作**之後**量測而誤報）。
3. **把「請求失敗」當成產品缺陷**：案例檔全空、`Expecting value: line 1 column 1` = 服務沒起來／連線失敗，
   不是 API 壞了（看容器狀態與啟動 log）。

---

## 4. 任務範本（可直接貼的具體指令）

### ① 以新版規格 ＋ 新資料集重建人設資料庫 ⭐（最常見）

> 讀 `tw-persona-db-rfc.md` 的「維度設計」「一致性規則」「每個人設的輸出格式」與 `concepts/` 的設計知識，
> 盤點 `sources/` 現有資料來源。接著以 **`<新資料集路徑>`** 取代／擴充現有來源，
> 依規格重建一組人設資料庫（維持 1069 位或依規格調整），輸出 `tw_persona_1069.json` 與新的權重表。
> 要求：① 每筆含全部維度 + `prompt_prefix` + `reference_pre_prompt` ② 命名遵循 RFC 規則
> ③ 完成後跑一致性驗證與矛盾獵捕，並產出**佔比對照表**（新舊分布差異）④ 權重表需標 `weight_version` 與資料年度
> ⑤ 產出 `REPORT-regen-<date>.md`：資料來源、方法、驗證結果、已知限制（含抽樣變異說明）。
> 全程遵守 `HANDOVER-PROMPT.md` 的五條鐵則。

### ② 新增一個維度（例：第 23 維）

> 依 `skills/persona-db-regen` 的決策樹：這是**新增維度** → 走**就地補註**。
> 步驟：① 在 RFC 新增該維度的定義與級距（含資料來源與依據）② 寫補註腳本對現有 1069 筆逐筆補值
> ③ 更新 `scripts/gen_dim_weights.py` 的可計分維度清單並重跑權重表
> ④ 更新維度可見性契約（`check_response_schema.py`）並在 API 回應與斷言中反映
> ⑤ 抽樣 30 筆人工覆核 ⑥ 出一版（新維度屬 `api/` 契約變更 → bump 版號）。

### ③ 重跑驗證並判讀

> 跑 `upDockerVerHermes/test-persona-db-api.sh`，把結果整理成報告：
> ① 紅旗統計 ② 每條斷言的判定與**掃描涵蓋數** ③ **空轉（未行使）項目要明列**並說明如何驗證
> ④ 任何異常先區分「產品缺陷／斷言問題／環境問題」再下結論 ⑤ 需要修的就開票（含修法與驗證方式）。

### ④ 出新版本（含部署）

> 依 `skills/persona-db-release`：bump 版號 → 打包（**去識別化＋守門掃描**）→ 部署 → 跑 SOP
> → 確認 0 紅旗與版本四者一致 → 產出 `RELEASE-<ver>.md`（含修的項目、相容性、驗證）→ 交付。

---

## 5. 已知限制（接手時先知道，不要當缺陷追）

- **API 查詢要 1–5 分鐘**（LLM 分析 ＋ 最多 3 輪放寬）→ 這是設計，不是效能問題。
  重複按「Execute」= 重新計費一次分析。
- **符合條件不足時會回少於要求筆數**（`pool_exhausted=true`）→ 系統**不為湊數**放寬題目核心維度。
- **過於嚴苛的題目會回 0 筆**（`status=too_strict`）→ 請拆題或減少限定。
- **受保護維度**：題目核心維度（例：醫美題的「有醫美經驗」）會被保護、不因樣本不足被放寬
  → 回應的 `protected_dims`／`warnings` 會說明。
- **`broadening_attempts` 的空轉與失敗輪**：`no_op`／`parse_error` 等旗標都是**揭露用**，
  代表系統誠實記錄，不代表故障。

---

## 6. 你會需要的三份技能文件

| 技能 | 什麼時候載入 |
|:--|:--|
| `skills/persona-db-regen/SKILL.md` | 要產出／修改資料集時 |
| `skills/persona-db-qa/SKILL.md` | 要驗證、判讀結果、寫斷言時 |
| `skills/persona-db-release/SKILL.md` | 要打包、部署、出貨時 |
