# persona-db API 實測分析報告 — NODE-A

**受測 instance**：`NODE-A` (tailscale `NODE-A`, `NODE-A.[tailnet]`)
**測試腳本**：`kstsai/persona-db-release` → `upDockerVerHermes/test-persona-db-api.sh`
**執行時間**：2026-09-12 02:25:5x → 02:45:07 UTC（≈ 19.4 分鐘）
**執行結果**：9 / 9 請求 HTTP 200，0 錯誤
**證據目錄**：`/Users/kstsai/Documents/personadb-NODE-A-api-verify/`

> ### 📌 量測範圍與判讀修正（2026-09-14 補記 — 僅附加，原文未改）
>
> **判讀修正請先看 [`../CORRECTIONS.md`](../CORRECTIONS.md)**：本報告是「**執行當時的判讀**」，
> 原文與原始證據保留不動（可追溯性）；後續取得新證據而推翻某條判讀時，修正記於該檔。
>
> | 項目 | 值 |
> |:---|:---|
> | runner sha256 | `ffc7b10642f72f4120a43b77848ed722c6cf865c23b3267a3eb87bd48c74695d`（**五輪完全相同** ⇒ 跨輪可比）|
> | runner 取得日期 | **2026-09-12**（第一輪取得；第 2–5 輪沿用**同一份凍結版**）|
> | 上游 upstream 副本 sha256 | `33749d4e5218f3860f15f4296c5fc5ea90f0fa93f441bc4eba9faf2274dad2e3`（**凍結版，90 行**）|
> | **現行 upstream**（2026-09-14） | `9a29a8ef3bc553a334b1865c792d4f0f17e60ce15f93a46fe9f8ac9b684edbd8`（**223 行**）|
>
> **⚠️ 覆蓋缺口（務必先讀）**：本輪 runner 的案例集取自第一輪的凍結版，**不含「業主本人」語意案例**。
> 其中**案例 08 是「顧客語意」**（問攤商的顧客），依現行設計**本就不該**套用 `employment_status=雇主`；
> 現行 upstream 亦已在標籤上註明「【顧客語意】不應套 employment_status」，並新增**案例 9「業主本人
> — dimension 22: employment_status（issue #34）」**。
>
> → 因此本報告中**任何「某維度從未被套用」的敘述，都必須先確認案例集有無該語意的案例**；
> 沒有案例即為**量測工件（coverage gap），不是產品缺陷**。詳見 `CORRECTIONS.md` 修正③ 與 issue #51。


---

## 1. 執行摘要

| # | 案例 | 標籤（腳本原文） | HTTP | 耗時(s) | bytes | total_matched | 回傳 | top score | domain |
|---|------|------------------|------|---------|-------|---------------|------|-----------|--------|
| 0 | `00_status` | `/personadb/status` | 200 | 0.86 | 792 | — | — | — | — |
| 1 | `01_kangshimei` | 康是美的目標客戶 | 200 | 185.39 | 3086 | 21 | 3 | 6.5499 | 零售/美妝/藥妝 |
| 2 | `02_tesla` | TESLA的目標客戶 | 200 | 80.90 | 2935 | 21 | 3 | 7.7196 | 汽車/電動車 |
| 3 | `03_fashion` | 時尚服裝設計師的目標客戶 | 200 | 167.79 | 5452 | 118 | 10 | 7.4629 | 時尚/服飾設計與零售產業 |
| 4 | `04_role_fangzhong` | 房貸優惠 — 房仲業者 | 200 | 223.11 | 3848 | 32 | 5 | 5.7728 | 房地產金融 |
| 5 | `05_role_banker` | 房貸優惠 — 銀行業者 | 200 | 199.12 | 3528 | 26 | 5 | 5.6547 | 房貸/房地產金融 |
| 6 | `06_aesthetic` | 醫美診所的目標客戶 | 200 | 84.50 | 4814 | 69 | 10 | 5.0374 | 醫療美容/消費醫療 |
| 7 | `07_debt` | 債務整合的目標客戶 | 200 | 124.96 | 4632 | 20 | 10 | 5.2411 | 金融/銀行貸款/債務整合 |
| 8 | `08_boss` | 小吃攤老闆的目標客群 | 200 | 87.19 | 4717 | 234 | 10 | 4.0163 | 餐飲/零售消費行為 |

**延遲**：`/personadb/status` 0.86s（無 LLM）；`/personadb/candidates` 80.9 – 223.1s，平均 **144.1s**，8 案例合計 1152.9s。延遲全部來自 LLM 篩選維度合成（每次呼叫都打 DeepSeek）。

**結構一致性**：8 個 candidates 回應全部具備相同 10 個 top-level key：
`status, total_matched, persona_ids, summary, important_dimensions, llm_analysis, relaxed_dims, broadening_attempts, applied_filters, scoring_basis`

**Contract 驗證**（`/openapi.json`，9298 bytes，4 個 endpoint：`/health`, `/personadb/candidates`, `/personadb/detail`, `/personadb/status`）：
- `top_k` 回傳量精確等於請求值，且 = `min(top_k, total_matched)` → **8/8 正確**
- `content-type` → candidates 8/8 `application/json`；status `text/plain; charset=utf-8`（與 OpenAPI 宣告一致）
- `persona_ids[i]` 與 `summary[i].id` 對應 **8/8 完全一致**（`TW-P-XXXX` 補零正確）
- `summary[].score` 單調遞減 **8/8 成立**

---

## 2. Instance 環境（`/personadb/status` 原文）

```
Version         v4.9.2
Main personas   1069 (tw_persona_1069.json, 1.60 MB)
Backup          ✅ 1069 (tw_persona_1069_backup.json)
QA (23 rules)   ✅ ALL CHECKS PASSED
Name diversity  171 unique names (16.0%), max repeat 15×
Python          3.11.16
Git             not a repo (filesystem boundary)
LLM             ✅ deepseek-v4-flash → https://api.deepseek.com (responsive)
Hermes Skills   3 total, 3 persona-related
Supporting Artifices: 30 Python files
QA Results: [R21] 0 violations / [R22] 0 violations / [R23] 0 violations
```

Server header：`uvicorn`。Tailscale：`active; direct [public-ip]:52036`（直連，非 relay），`Online: true`，node key 到期 `2027-01-20`。
**注意**：`Name diversity` 顯示 171 unique / 1069 = 16.0%，`max repeat 15×` — 名字重複率高（案例 06/07 中 `雅芳` 出現於 797 與 802 兩個不同 persona）。此為已揭露的既有現象，非本次測試失敗。

---

## 3. 逐案例詳細分析

> 以下 `applied_filters` 為 LLM 合成的實際篩選條件；`important_dimensions` 為 LLM 認定的重要維度（**與 applied_filters 不同**，見 §4.4）。

### 案例 1 — 康是美的目標客戶（top_k=3, opMode=僅篩選）

- **回應**：`total_matched=21`，回傳 3 筆，score `6.5499 / 6.4962 / 6.0622`
- **personas**：891 小薇(25-34 服務 南投縣) / 398 麗華(35-44 公務 台中市) / 907 淑娟(35-44 家管 雲林縣) — **3/3 女性**
- **applied_filters**：age `19-24,25-34,35-44`｜**sex `女`**｜occupation 9 類｜income `無收入,<3萬,3-8萬,>8萬`（**全 4 桶**）｜family_income 3 桶｜clothing_spend `500~1500,1500~3000,3000~5000`｜commute_mode `捷運/公車,機車`｜education 3 類
- **relaxed_dims**：`hobby`；**broadening 3 輪**：6 → 13 → 18 → 21
- **分析**：`sex=女` 有下、結果 3/3 女性 → 與 LLM 自述 `target_user`（女性）**一致**。但 `income` 濾網開放全部 4 桶，回傳卻 3/3 都是 `>8萬` 且 `family_income=>8萬` → 顯示**排序權重由最高收入桶主導**，而非濾網決定（見 §4.1）。
- **矛盾點**：`clothing_spend` 上限設在 `3000~5000`（排除 `>5000`），但 top-1 (891) 與 top-2 (398) 的 `clothing_spend` 正是 `3000~5000`，屬邊界值；`applied_filters` 與 `summary` 無衝突。

### 案例 2 — TESLA的目標客戶（top_k=3）

- **回應**：`total_matched=21`，3 筆，score `7.7196 / 7.4513 / 7.3817`（**全場最高分**）
- **personas**：1000 麗華(35-44 科技 屏東縣) / 804 明義(45-54 科技 宜蘭縣) / 364 麗美(35-44 科技 高雄市) — **3/3 科技業、3/3 `>8萬`**
- **applied_filters**：age `25-34,35-44,45-54`｜occupation `科技,金融,自營`｜**income `>8萬`（單一桶）**｜family_income `>8萬,7萬`｜family_size `2,3,4`｜**commute_mode `汽車,機車,捷運/公車`**｜clothing_spend `>5000,3000~5000`｜education `大學,研究所以上`｜housing_burden `低,中`
- **relaxed_dims**：`[]`；**broadening 1 輪**：9 → 21
- **分析**：`income=>8萬` 是**唯一**被鎖死的維度，與「高單價耐久財」語意相符 → 內容效度良好。惟 `commute_mode` 同時納入 `汽車/機車/捷運公車`（等於未限制），使該維度失去區辨力；LLM 自述要「以通勤方式區分購車潛力」，實際濾網卻未落實 → **自述意圖與實作濾網不一致**。
- **broadening 語意值得注意**：`relaxed_dims` 為空，但仍有 1 輪 broadening（9→21）—— broadening 可透過「放寬維度內的值域」達成，不需刪除整個維度。此與案例 1/3/4/5 的「刪除維度」型 broadening 是兩種不同機制。

### 案例 3 — 時尚服裝設計師的目標客戶（top_k=10）

- **回應**：`total_matched=118`，10 筆，score `7.4629 → 6.2122`
- **applied_filters**：age `25-34,35-44,45-54`｜occupation 10 類（含 `其他,製造`）｜income `3-8萬,>8萬`｜clothing_spend `1500~3000,3000~5000,>5000`｜family_income `5-7萬,7萬,>8萬`｜education `大學,研究所以上,高中`
- **relaxed_dims**：`hobby`；**broadening 3 輪**：1 → 1 → 11 → 118
- **分析**：**top-10 全數 `clothing_spend >= 1500`，其中 6 筆為 `>5000`**，且 10/10 `income=>8萬`、`family_income=>8萬` → 服飾消費維度確實生效，是本批次中**濾網與結果最貼合語意**的案例之一。
- **⚠️ 疑點**：LLM 的 `target_user` 寫成 *「時尚服裝設計師、時尚品牌創業者、服飾零售業者…」*（即**把發問者本身當成目標客戶**），而 `reasoning` 卻說「屬於時尚服飾消費行為領域，需要考慮服飾消費能力與相關職業」。`target_user` 與 `reasoning` **互相矛盾**；實際濾網（高服飾消費族群）才是正確方向 → `target_user` 欄位語意錯誤。此為**欄位內容品質問題**，值得上游修正。
- **broadening 第 1 輪 1→1**（無效迴圈）：`change` 文字有寫，`match_count_before == after`，屬**空轉迴圈**。

### 案例 4 — 房貸優惠方案 / role=房仲業者（top_k=5）

- **回應**：`total_matched=32`，5 筆，score `5.7728 / 5.7728 / 5.6297 / 5.6297 / 5.4955`（**2 組同分**）
- **personas**：408 世昌(45-54 科技 台南市) / 1004 文彬(45-54 科技 嘉義縣) / 237 柔伊(25-34 公務 台北市) / 277 艾倫(25-34 公務 桃園市) / 997 美珍(35-44 科技 嘉義市)
- **applied_filters**：age `25-34,35-44,45-54`｜income `3-8萬,>8萬`｜**marriage `已婚`**｜family_size `3,4`｜**housing_burden `低,中`**｜family_income `5-7萬,7萬,>8萬`
- **relaxed_dims**：`occupation`；**broadening 3 輪**：4 → 8 → 14 → 32
- **分析**：**`housing_burden=低,中`** — 房仲找的是「現有居住負擔輕 → 有餘裕購屋/換屋」的族群，語意正確且與案例 5 形成明確對比。`marriage=已婚`、`family_size=3,4` 亦符合換屋需求輪廓。放寬 `occupation` 後職業不再是限制（applied_filters 中確實無 occupation）→ **`relaxed_dims` 與 `applied_filters` 一致**。

### 案例 5 — 房貸優惠方案 / role=銀行業者（top_k=5）

- **回應**：`total_matched=26`，5 筆，score `5.6547 / 5.6421 / 5.5668 / 5.5502 / 5.4931`
- **personas**：331 強哥(35-44 醫療 台南市) / 914 雅雯(35-44 公務 苗栗縣) / 597 寶珠(55-64 公務 桃園市) / 826 國華(55-64 科技 基隆市) / 797 雅芳(35-44 醫療 新竹市)
- **applied_filters**：age `35-44,45-54,55-64`｜occupation `科技,金融,公務,製造,醫療`｜**income `>8萬`（單一桶）**｜**housing_burden `中,高`**｜family_income `>8萬,7萬`
- **relaxed_dims**：`marriage`；**broadening 2 輪**：17 → 17 → 26
- **分析**：**`housing_burden=中,高`** + 年齡上移至 `55-64` — 銀行找的是「**已有房貸、負擔較重、可轉貸**」的既有貸戶，與案例 4（房仲，負擔輕的潛在購屋者）**方向完全相反且語意正確**。

#### ★ Role 差異化驗證（腳本 §Role QA）

| 項目 | 房仲業者 | 銀行業者 |
|------|----------|----------|
| top-1 persona | **408**（45-54 科技） | **331**（35-44 醫療） |
| top-5 集合 | {408,1004,237,277,997} | {331,914,597,826,797} |
| **交集** | **0 筆（完全不相交）** | |
| housing_burden | `低,中` | `中,高` |
| age 上限 | `45-54` | `55-64` |
| income | `3-8萬,>8萬` | `>8萬` |
| relaxed_dim | `occupation` | `marriage` |

→ **✅ DIFFERENT — role 確實生效**。不僅 top-1 不同，**整個 top-5 完全不重疊**，且 `housing_burden` 方向相反。這是本批次**最強的正向驗證結果**。

### 案例 6 — 醫美診所的目標客戶 / role=醫美診所行銷主管（top_k=10）

- **回應**：`total_matched=69`，10 筆，score `5.0374 → 4.7175`
- **applied_filters**：age `25-34,35-44,45-54`｜occupation `科技,金融,服務,自營`｜income `3-8萬,>8萬`｜clothing_spend `1500~3000,3000~5000,>5000`｜family_income `5-7萬,7萬,>8萬`｜**無 sex 維度**
- **relaxed_dims**：`[]`；**broadening：無（0 輪）** — 首次查詢即達標
- **分析**：
  - **⚠️ 性別未篩選，回傳 6 男 / 4 女**（實查 `/personadb/detail`）：208 男、770 男、337 男、189 男、213 男、252 女、382 女、802 女、817 女、199 男。醫美在台灣屬**女性高度傾斜**的消費類別，且 `llm_analysis.target_user` 與 `important_dimensions` 都提到「注重外表」與 `sex`，但 **`applied_filters` 完全沒有 sex**。對照案例 1（康是美，同樣女性傾斜）**有**下 `sex=女` 且 3/3 女性 → **同一模型對同性質類別的性別篩選行為不一致**。
  - 10/10 `income=>8萬`、`family_income=>8萬` — 但 `applied_filters.income` 明明包含 `3-8萬`。
  - **案例標籤宣稱測 `dimension 20: aesthetic_procedure`，但該維度不存在**（見 §4.3）。

### 案例 7 — 債務整合貸款方案的目標客戶 / role=銀行債務整合專員（top_k=10）

- **回應**：`total_matched=20`（**本批次最少**），10 筆，score `5.2411 → 4.6554`
- **applied_filters**：age `35-44,45-54`｜occupation `科技,金融,自營,公務,醫療`｜**income `>8萬`（單一桶）**｜**housing_burden `中,高`**｜**family_income `>8萬`（單一桶）**
- **relaxed_dims**：`[]`；**broadening：無（0 輪）**
- **分析**：`role` 確實改變了濾網方向（與案例 4 的房仲同題不同 role）。`housing_burden=中,高` 符合「既有房貸、還款壓力」語意，與 LLM 自述 `target_user`（40-55 歲、還款壓力中高）大致吻合。
- **⚠️ 注意**：`total_matched=20` 恰等於 `top_k=10` 的 2 倍，且**無 broadening** → 濾網偏緊但未觸發放寬。
- **案例標籤宣稱測 `dimension 21: debt_status`，但該維度不存在**（見 §4.3）；「債務狀態」實際被 `housing_burden` + `income` 代理。
- LLM 自述 `family_income` `>8萬` 與實作一致；但**「債務整合」鎖定家庭所得最高桶**在業務邏輯上值得商榷（高所得者通常非債務整合主要客群）—— 這是**語意/業務合理性**的可檢討點，惟與 API 契約無關。

### 案例 8 — 小吃攤老闆的目標客群 / role=夜市商圈協會（top_k=10）

- **回應**：`total_matched=234`（**本批次最大**），10 筆，score `4.0163 → 3.4557`（**全場最低分**）
- **applied_filters**：age `19-24,25-34,35-44`｜occupation `學生,服務,製造,科技`｜**income `無收入,<3萬,3-8萬`**（**排除 `>8萬`**）
- **relaxed_dims**：`[]`；**broadening：無（0 輪）**
- **分析**：**唯一與其他 7 案例反向的案例** —— 全場唯一「低收入」結果集（`income=>8萬` = **0/10**）。10 筆**全部**為 19-24 歲；其中 **8 筆為 `學生`／`無收入`**，另 1 筆 `服務`、1 筆 `製造`。與「小吃攤＝平價、便利」的消費邏輯相符 → **內容效度良好**，也證明 scorer **並非**無條件偏好高收入（見 §4.1 的修正）。
- **⚠️ 重大語意歧義**：`applied_filters.occupation` 為 `學生,服務,製造,科技`，**明確排除 `自營`**。但案例標籤宣稱此案例測 `dimension 22: employment_status`（就業狀態），且查詢字面「**小吃攤老闆**的目標客群」可解讀為「**以小吃攤老闆（自營）為目標客群**」（例如賣設備、貸款、進貨服務）。LLM 選擇解讀為「**小吃攤的顧客**」，因此把 `自營` 排除 —— **與案例標籤的測試意圖相反**。此為**查詢語意歧義未被澄清**的案例，建議測試腳本改用無歧義措辭（例如「小吃攤的顧客輪廓」vs「小吃攤創業貸款的目標客群」）。

---

## 4. 跨案例發現（Cross-cutting findings）

### 4.1 【高】收入桶飽和 — 7/8 案例回傳 100% `>8萬`

| 案例 | `income=>8萬` | `family_income=>8萬` | applied_filters.income |
|------|---------------|----------------------|------------------------|
| 01 康是美 | **3/3** | 3/3 | 無收入,<3萬,3-8萬,>8萬 |
| 02 TESLA | **3/3** | 3/3 | >8萬（單桶） |
| 03 時尚 | **10/10** | 10/10 | 3-8萬,>8萬 |
| 04 房仲 | **5/5** | 5/5 | 3-8萬,>8萬 |
| 05 銀行 | **5/5** | 5/5 | >8萬（單桶） |
| 06 醫美 | **10/10** | 10/10 | 3-8萬,>8萬 |
| 07 債務整合 | **10/10** | 10/10 | >8萬（單桶） |
| 08 小吃攤 | 0/10 | 1/10 | 無收入,<3萬,3-8萬 |

**在 7 個案例中，`top_k` 完全被最高收入桶佔滿**。最值得注意的是**案例 01 與 06**：`applied_filters.income` 都**開放**了 `3-8萬`，甚至案例 01 開放了全部 4 桶，排序結果卻仍 100% 落在 `>8萬`。

→ **判讀**：這是**排序權重**（scoring）而非濾網（filter）造成的頭部集中。同一現象在案例 08 反向出現（排除 `>8萬` 後，結果集中於最低收入桶），顯示 scorer 對收入維度賦予**主導性權重**，使其他維度難以體現差異。

→ **建議**：對「目標客群 ≠ 最高收入族群」的題型（醫美、藥妝、債務整合、小吃攤），`top_k` 的**代表性**偏低。若下游要做問卷模擬，建議 (a) 在 `applied_filters` 後對結果做分層抽樣，或 (b) 開放 scoring 權重調整參數。

**影響範圍**：8 案例中 7 案例；直接影響下游問卷/模擬的代表性。

### 4.2 【高】Non-determinism — 相同查詢、兩次執行，結果不重複

測試期間曾因前景執行逾時中斷一次（Run A，02:15–02:24 UTC），隨後完整重跑（Run B，02:25–02:45 UTC）。**兩次使用完全相同的 URL 與參數**：

| 案例 | Run A matched | Run B matched | Run A ids | Run B ids | **交集** | Run A top | Run B top |
|------|---------------|---------------|-----------|-----------|----------|-----------|-----------|
| 01 康是美 | 26 | 21 | 185, 877, 176 | 891, 398, 907 | **0 / 3** | 4.7964 | 6.5499 |
| 02 TESLA | 21 | 21 | 770, 1062, 382 | 1000, 804, 364 | **0 / 3** | 6.8883 | 7.7196 |
| 03 時尚 | 69 | 118 | 213,208,288,802,324,793,195,337,286,770 | 244,480,286,891,213,288,337,770,797,252 | **5 / 10** | 5.7034 | 7.4629 |

**實證差異不只結果集，連 `applied_filters` 都不同**：
- 案例 01：Run A `income=[無收入,<3萬,3-8萬]`、broadening `5→9→26`、relax 說明為「放寬職業維度」；Run B `income=[無收入,<3萬,3-8萬,>8萬]`、broadening `6→13→18→21`。
- 案例 02：Run A `commute_mode=[汽車]`（合理）；Run B `commute_mode=[汽車,機車,捷運/公車]`（退化為無限制）。Run A `income=[3-8萬,>8萬]`；Run B `income=[>8萬]`。

→ **判讀**：`/personadb/candidates` 每次呼叫都以 LLM **重新合成**篩選維度與值域，因此**端點不可重現**（non-reproducible）。`total_matched`、`persona_ids`、`score`、`applied_filters` 全部會變。

→ **對測試腳本的衝擊**：`Role QA: diff check` 這類斷言在單次執行中通過（408 vs 331），但**不具備統計保證** —— 若 role 差異小於 LLM 抽樣變異，此檢查會**偽陽性通過**。建議改為多次取樣後比較分布（例如各跑 5 次比較 top-5 集合的重疊率）。

→ **Run A 原始證據已完整保存**於 `runA/`（非僅日誌殘留）。

### 4.3 【中】案例標籤宣稱的 dimension 20/21/22 不存在於 persona schema

腳本標籤寫明案例 6/7/8 分別測試 *「dimension 20: aesthetic_procedure」「dimension 21: debt_status」「dimension 22: employment_status」*。

**實測**：
- 對 8 個 persona（含各案例回傳的 208/337/181/891/408/331/244/802）呼叫 `/personadb/detail`，**每個 persona 都恰好 22 個維度**，且 8 個樣本的維度集合**完全一致**：
  `age, background_story, city_income_tier, city_price_tier, clothing_spend, commute_mode, education, family_income, family_size, hobby, housing_burden, housing_cost, income, marriage, media_diet, occupation, political_issues, political_stance, politics, region, residence, sex`
- 在**全部 9 個回應**（`raw/*.body`）中搜尋字串 `aesthetic_procedure` / `debt_status` / `employment_status` → **0 次出現**（遍及 `applied_filters`、`important_dimensions`、`scoring_basis.dims_counted`）。

→ **判讀**：這 3 個維度**不存在於目前運行的 persona schema**（v4.9.2，1069 personas）。案例標籤描述的是**預期/規劃中**的維度，非實際 schema。因此案例 6/7/8 實際上**並未測到**標籤所指的維度，而是以既有維度代理：
- `aesthetic_procedure` → 被 `clothing_spend` + `income` 代理
- `debt_status` → 被 `housing_burden` + `income` 代理
- `employment_status` → 被 `occupation` 代理（且案例 8 反而排除了 `自營`）

→ **建議**：釐清 dimension 20/21/22 是「尚未部署」還是「編號定義不同」（目前 schema 的第 20/21/22 個維度依字母序為 `politics, region, residence`）。測試腳本的標籤應與實際 schema 對齊，否則會產生「已測試」的假象。

### 4.4 【中】`scoring_basis.dims_counted` 低報實際使用的維度

`scoring_basis` 宣稱評分方法為 `log-frequency × cross-dim normalized [0.5, 2.0]`，並列出 `dims_counted`。若此宣告為真，則**在 `dims_counted` 上值完全相同的 persona 必須同分**。

**實測反例**（分數不同，但 `dims_counted` 向量完全相同）：

| 案例 | dims_counted | 反例 |
|------|--------------|------|
| 03 時尚 | age,occupation,income,clothing_spend,family_income,education,hobby | **2 組** |
| 05 銀行 | age,occupation,income,marriage,housing_burden,family_income | **1 組** |
| 06 醫美 | age,occupation,income,clothing_spend,family_income | **2 組** |
| 07 債務 | age,occupation,income,housing_burden,family_income | **3 組** |
| **08 小吃攤** | **age,occupation,income** | **25 組** |

**最具體的證據（案例 08）** — 三筆 persona 的 `age|occupation|income` **完全相同**，分數卻不同：

| persona | 分數 | age | occupation | income | family_income | clothing_spend | housing_burden |
|---------|------|-----|------------|--------|---------------|----------------|----------------|
| 0181 小奈 | **4.0163** | 19-24 | 學生 | 無收入 | **>8萬** | **>5000** | 低 |
| 0149 阿緯 | **3.6190** | 19-24 | 學生 | 無收入 | **7萬** | **500~1500** | 中 |
| 0138 小白 | **3.5868** | 19-24 | 學生 | 無收入 | **1-3萬** | **<500** | 低 |

分數與**未宣告**的 `family_income` / `clothing_spend` **單調相關**。

案例 07 亦同：337 建宏 vs 1062 大仁 —— `dims_counted` 六維全同，但 `city_price_tier` 為 `中` vs `極低`、`clothing_spend` 為 `1500~3000` vs `500~1500`，分數 5.2411 vs 5.1229。

→ **判讀**：實際 scorer **使用了 `dims_counted` 未列出的維度**（至少 `family_income`、`clothing_spend`、`city_price_tier`/`residence`）。`scoring_basis` 的自我描述**不完整**，無法據以重算或稽核分數。

→ **建議**：`dims_counted` 應列出真正參與計分的所有維度，否則對外揭露的計分基礎具誤導性。

### 4.5 【低】同分（tie）機制 — 可解釋、但暴露維度覆蓋

本批次出現 9 組同分，全部屬「`dims_counted` 值相同、僅 `residence` 不同」：

| 案例 | 分數 | 配對 |
|------|------|------|
| 04 | 5.7728 | 0408 世昌(台南市) / 1004 文彬(嘉義縣) |
| 04 | 5.6297 | 0237 柔伊(台北市) / 0277 艾倫(桃園市) |
| 06 | 4.7638 | 0189 艾力克(桃園市) / 0213 班(高雄市) |
| 06 | 4.7255 | 0382 婉玲(台中市) / 0802 雅芳(新竹縣) |
| 07 | 5.0259 | 0797 雅芳(新竹市) / 0996 麗美(嘉義市) |
| 07 | 4.6649 | 0382 婉玲(台中市) / 0802 雅芳(新竹縣) |
| 08 | 3.6190 | 0149 阿緯(台中市) / 0151 阿豪(新北市) |
| 08 | 3.5868 | 0138 小白(台中市) / 0172 小艾(台南市) |
| 08 | 3.5114 | 0139 大雄(台南市) / 0185 若希(高雄市) |

→ 在**案例 01/02/04** 中，「同分 ⇔ 計分維度向量相同」**完全成立**（無反例）；但在**案例 03/05/06/07/08** 有反例（§4.4）。→ `residence` 在部分案例不計分（造成同分），在部分案例卻計分（造成 §4.4 反例）—— **計分維度集合似乎每次呼叫都可能不同**，這與 §4.2 的 non-determinism 一致。

### 4.6 【低】`broadening_attempts` 可能空轉，且 relaxation 機制有兩種

- **空轉迴圈**：案例 03 第 1 輪 `match_count_before=1 → match_count_after=1`（無效），但仍記錄為一輪。
- **兩種 broadening 機制**：
  - (a) **刪除維度** → 同步反映在 `relaxed_dims`（案例 01 `hobby`、03 `hobby`、04 `occupation`、05 `marriage`）
  - (b) **放寬維度內值域** → `relaxed_dims` 為空（案例 02，9→21）
- **一致性良好**：4 個有 `relaxed_dims` 的案例，其 `applied_filters` 中**確實找不到**該維度 → `relaxed_dims` 語意可信。
- **0 輪 broadening 的案例**：06（69 matched）、07（20 matched）、08（234 matched）— 首次查詢即達標，其中 07 的 20 筆相對偏少卻未觸發放寬。

### 4.7 【低】`llm_analysis.usage_suggestion` 全場無區辨力

8/8 案例的 `usage_suggestion.mode` 皆為 `問卷答題者`，`recommended_opMode` 皆為 `僅篩選`（與請求的 `opMode=僅篩選` 一致）。
→ 此欄位在本測試集為**常數**，無區辨資訊；`recommended_opMode` 與請求一致這點是正向的（無反向建議），但無法證明它會在不同 `opMode` 下正確變化（本次未測其他 `opMode` 值）。

---

## 5. 驗證限制 / 未涵蓋範圍

1. **未測 `opMode` 其他值**：全部 8 案例固定 `opMode=僅篩選`（與腳本一致）。`篩選+模擬` / `模擬詢問` 的行為**未經驗證**。
2. **未測 `/personadb/detail` 的完整契約**：僅用於補充查維度與性別，非腳本範圍（本報告已標示為 supplementary）。
3. **未測 `top_k` 邊界**（1 / 100 / 0 / >100）與錯誤路徑（400 / 500）。
4. **未測 `questions` 多題以 `|` 分隔**的行為（OpenAPI 有此宣告，腳本未涵蓋）。
5. **`aesthetic_procedure` 等維度的不存在**，是基於 8 個 persona 樣本 + 全部 9 個回應的字串搜尋；**未直接讀取 `tw_persona_1069.json`**（該檔案位於 instance 上，本次未取得）。若需 100% 確認，應在 instance 上檢查 persona JSON 的完整 key 集合。
6. **分數無法獨立重算**：因 §4.4 的 `dims_counted` 不完整，且權重來源（DGBAS 113 年家庭收支調查等）未隨回應提供，**分數正確性未被驗證**（僅驗證了單調性與 tie 結構）。
7. **樣本數 = 1 輪**：除 §4.2 的 3 個案例有 2 輪資料外，其餘案例僅 1 次執行；LLM 變異未做統計估計。

---

## 6. 結論

**通過（正向驗證）**
- 9/9 HTTP 200，無 5xx / 4xx；OpenAPI 契約與實際回應一致（content-type、key 集合）。
- `top_k` 精確遵守（8/8）；`persona_ids` ↔ `summary.id` 對應正確（8/8）；分數單調遞減（8/8）。
- **`role` 參數確實生效**（案例 4 vs 5）：top-5 **完全不重疊**，且 `housing_burden` 方向相反（房仲 `低,中` vs 銀行 `中,高`）— 語意正確。
- `relaxed_dims` 與 `applied_filters` **完全一致**（4/4）。
- 案例 08 證明 scorer **不是**無條件偏好高收入（低收入案例正確產出低收入客群）。

**待處理問題（依嚴重度）**
1. **收入桶飽和**（§4.1，7/8 案例 100% `>8萬`）— 影響下游問卷代表性。
2. **端點不可重現**（§4.2，同 query 兩次執行 top-3 交集 0）— 影響所有斷言式 QA 的可信度。
3. **案例標籤宣稱的 dimension 20/21/22 不存在**（§4.3）— 測試覆蓋率被高估。
4. **`scoring_basis.dims_counted` 低報計分維度**（§4.4，案例 08 有 25 組反例）— 計分基礎無法稽核。
5. **案例 06 醫美未篩性別、回傳 6 男/4 女**（§3 案例 6）— 內容效度問題。
6. **案例 08 查詢語意歧義**，實際排除 `自營`，與標籤測試意圖相反（§3 案例 8）。
7. **案例 03 `target_user` 欄位語意錯誤**（把發問者當目標客戶），與同回應 `reasoning` 矛盾（§3 案例 3）。

---

## 7. 本次相對於原腳本的改動（供複驗者對照）

原始腳本 `test-persona-db-api.sh`（sha256 `33749d4e…dad2e3`）設計為**在 instance 本機**執行（`http://localhost:8000`）。本次為**遠端對 NODE-A 執行**，改動如下：

| 項目 | 原腳本 | 本次 | 理由 |
|------|--------|------|------|
| Base URL | `http://localhost:8000` | `http://NODE-A:8000`（tailscale） | 從 DSH host 遠端執行 |
| 證據保存 | 僅 case 3 存 `fashion_closing.json`，其餘只印出 | 每案例存 `raw/*.body` + `headers/*.headers` + `meta/*.meta` | 完整保存以利人類複驗 |
| Role QA diff check | `python3` 讀 `/tmp/role_fangzhong.json` | `jq` 讀 `json/04_*.json` | 避免依賴 `/tmp` 路徑；等效 |
| 請求參數 | — | **完全不變**（同樣的 URL、參數、順序、`opMode=僅篩選`） | 保持忠實 |

**腳本、順序、參數、斷言邏輯皆與原版一致**；僅調整 base URL、證據落盤方式與 diff check 的解析工具。改動後腳本 sha256：`ffc7b106…74695d`（見 `meta/script-provenance.txt`）。
