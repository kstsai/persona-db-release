# LLM Verify QA Reports — persona-db API 實測

> **同一份測試腳本**（`upDockerVerHermes/test-persona-db-api.sh`）對受測環境執行，
> 逐案例保存 **byte 級證據**。
>
> 方法論：`api-version-sweep` skill（dsh 系共用 kit）。
> 執行者：dsh1（DeepSeek Harness）。
>
> ⚠️ **方法在第九輪改變**：skill **v2.0.0**（2026-09-14 依 kstsai 指示）**取消跨版本比對**，
> 之後每一輪**只分析當前版本的回應**。第 1–8 輪的跨輪材料與 `compare-nway.py` 保留為**歷史紀錄**；
> **第 9 輪起不再產出 `version-comparison-nway.csv`，也不參與跨輪對照**。

> **⚠️ 判讀修正請先看 [`CORRECTIONS.md`](CORRECTIONS.md)** —— 個別報告的判讀若被後續證據推翻（例如取得伺服器端 log），修正記於該檔，**原文保留不動**。

> **判讀修正回饋路徑（2026-09-14 定案）**：任何人取得新證據而能推翻某條判讀時 ——
> 1. **先寫進 `CORRECTIONS.md`**（編號、原判讀、修正、**證據**、對外使用建議）；
> 2. 若該教訓可一般化 → **回寫**產出該報告的方法論 skill（`api-version-sweep` 等）；
> 3. **下一輪報告引用該修正編號**，不重複同樣的誤報。
>
> 觸發紀錄：`http=000` 與「維度從未被套用」兩類誤報**各已重複出現一次以上**，
> 同屬「用症狀歸因、未先取得那一側證據」的根因 —— 前者已補進 skill Step 7（hermesa3），
> 後者補為「覆蓋斷言」（dsh1）。

---

## 十二輪一覽

| # | 版本 | 節點 | runner | 日期 | 契約 sha256(16) | 結果 | 該輪重點 |
|:-:|:-----|:-----|:-----|:-----|:----------------|:-----|:---------|
| 1 | **v4.9.2** | `NODE-A` | 凍結 90 行 | 2026-09-12 | `8ac54b95228d85fc` | 9/9 | 基線。發現 `aesthetic_procedure`/`debt_status`/`employment_status` **不存在** |
| 2 | **v5.2** | `NODE-B` | 凍結 | 2026-09-12 | `8b869ae266992056` | 9/9 | **+3 維度**（25 維）並投入運作；樣本變異達 **62×** |
| 3 | **v5.3.1** | `NODE-A` | 凍結 | 2026-09-12 | `8b869ae266992056` | 9/9 | 純行為 patch（契約同 v5.2）；`dims_counted` 修正為 0 不一致 |
| 4 | **v5.4** | `NODE-B` | 凍結 | 2026-09-12 | `30a228782154bdce` | **8/9** | +`pool_exhausted`/`returned`/`no_op`/`overshoot`/`score_scale`；首見 503 且**該回應違反自身宣告 schema** |
| 5 | **v5.6** | `NODE-B` | 凍結 | 2026-09-13 | `aafe647f46ee8abe` | 9/9 | **契約型別化**（落實第 4 輪建議）；延遲 98.2s |
| 6 | **v5.6** | `NODE-B` | **upstream 223 行** | 2026-09-14 | `aafe647f46ee8abe` | **10/10** | **結案 issue #51**（`employment_status` 實為量測工件）；負向測試**驗收 #47 已修復** |
| 7 | **v5.6** | `NODE-A` | upstream 223 行 | 2026-09-14 | `aafe647f46ee8abe` | **10/10** | **主機端驗收**（Docker 部署）：語意正確性 9/9；**判讀不跨版本比對**，聚焦 response 內容分析 |
| 8 | **v5.7** | `NODE-B` | **upstream 227 行** | 2026-09-14 | **`cb5b08084daea8af`** | **10/10** | **上游斷言 13/13 全過**；`summary` 擴充 **17→24 欄**（回應可自我驗證）；**不與前版本比對** |
| 9 | **v5.8** | `NODE-A` | **upstream 301 行** | 2026-09-14 | **`6d3c1508b53a3f56`** | **10/10** | 斷言 **31✅/1⚠️/0❌/0 N/A**（**首次在節點本機執行 ⇒ 沒有 N/A**）；`#42` 的 ⚠️ 證實為「放寬把分析步驟認定的必要維度移掉」（案例 07 同案例自我矛盾、8→58）；**案例 06/09 重跑不可重現**；**不與前版本比對** |
| 10 | **v5.10** | `NODE-A` | **upstream 372 行** | 2026-09-15 | **`588772d4afbc095e`** | **10/10** | 斷言 **42✅/0⚠️/0❌/0 N/A**；**核心維度保護（`protected_dims`）經重跑驗證有效**（`protected ∩ relaxed = ∅` 4/4）；定向探針**逼出硬性 veto**（`protected_veto`）；`status` 語意 18/18；10 輪放寬 **0 空轉 0 overshoot**；**不與前版本比對** |
| 11 | **v5.11.1** | `NODE-A` | **upstream 421 行** | 2026-09-15 | **`c17043b4022fbb32`** | **10/10** | 斷言 **44✅/1⚠️/0❌/0 N/A**；**第十輪三條建議皆已落地並驗證有效**（`widened_dims` 留痕／`#62` 空值清單守門／K/L/M veto 不變式被採納）；保護 **8/8 成立**、逼出 2 個真實 veto；**但 case08「顧客語意」是雙峰（4 次中 2 次反轉），回應不會警示**；**不與前版本比對** |
| 12 | **v5.12** | `NODE-A` | **upstream 480 行** | 2026-09-15 | **`38009c9f310177aa`** | **10/10** | 斷言 **53✅/0⚠️/0❌/1ℹ️**；**`#65` 主體護欄把第十一輪的雙峰收斂**（顧客語意 4/4 判為 `customer`，同質化矩陣無 ≥8/10 配對）；**但採納的 S/T 不變式用過嚴形式**（本輪 `05_role_banker` 為新假警報實例，且它只掃 4/9 案例所以沒報錯）；`warnings`／剝除路徑**未被行使**；**不與前版本比對** |

**共 9 種不同契約**（v5.2 與 v5.3.1 同 hash ⇒ 純行為 patch；第 5–7 輪同為 `aafe647f`；v5.7 `cb5b0808`；v5.8 `6d3c1508`；v5.10 `588772d4`；v5.11.1 `c17043b4`；**v5.12 為新契約 `38009c9f`**）。

> ⚠️ **第 5 輪與第 6 輪版本、契約完全相同，只差 runner**。兩輪案例 1–8 的 **query 與參數完全相同**
> （已機械比對），故其差異**純屬 LLM 抽樣**、**不可歸因於 runner** —— 這組對照反而提供最乾淨的
> 「同一版本純抽樣變異」樣本（案例 03：`21 → 105`，5×）。

---

## 目錄

```
qa-reports/
├── README.md                              ← 本檔（索引）
├── CORRECTIONS.md                         ← 判讀修正紀錄（單一修正來源）
├── round1-v4.9.2-nodeA/                   ← 第 1 輪
├── round2-v5.2-nodeB/                     ← 第 2 輪
├── round3-v5.3.1-nodeA/                   ← 第 3 輪
├── round4-v5.4-nodeB/                     ← 第 4 輪
├── round5-v5.6-nodeB-frozenrunner/        ← 第 5 輪（凍結 runner）
├── round6-v5.6-nodeB-upstreamrunner/      ← 第 6 輪（upstream runner）
├── round7-v5.6-nodeA-upstreamrunner/      ← 第 7 輪（同 runner，`NODE-A` Docker 部署；**不做版本比對**）
├── round8-v5.7-nodeB-upstreamrunner/      ← 第 8 輪（**v5.7**，upstream 227 行；**不做版本比對**）
├── round9-v5.8-nodeA-upstreamrunner/      ← 第 9 輪（**v5.8**，upstream 301 行；**節點本機執行**；**不做版本比對**）
├── round10-v5.10-nodeA-upstreamrunner/    ← 第 10 輪（**v5.10**，upstream 372 行；節點本機執行；**不做版本比對**）
├── round11-v5.11.1-nodeA-upstreamrunner/  ← 第 11 輪（**v5.11.1**，upstream 421 行；節點本機執行；**不做版本比對**）
└── round12-v5.12-nodeA-upstreamrunner/    ← 第 12 輪（**v5.12**，upstream 480 行；節點本機執行；**不做版本比對**）
```

> **命名 = `round<輪次>-v<版本>-node<代號>[-<runner 別>]`。** 三個理由：
> 1. **輪次**在最前 → 目錄排序即時間順序（跨版本對照時不易搞混）
> 2. **節點用代號** → 本 repo 為 public，不揭露實際節點（原以節點命名會直接洩漏）
> 3. **第 5、6 輪同版本但 runner 不同** → 名稱必須區分，否則兩者的差異會被誤讀成版本差異
>
> 各包 `README.md` 的複驗指令以**相對路徑**互相引用，改名時已同步更新（21 檔），
> 且所有指令均重新實跑驗證。

---

## 節點代號約定（去識別化）

本目錄為 **public repo**，報告以**代號**標示受測節點，不揭露可路由資訊：

| 代號 | 對應 |
|:---|:---|
| `NODE-A` | 第一／三／七／九／十／十一／十二輪的受測節點 |
| `NODE-B` | 第二／四／五／六／八輪的受測節點（同一節點多次就地升級）|
| `NODE-B-host` | `NODE-B` 的節點內部 HostName（與 tailnet 名不同）|
| `[public-ip]` / `[ts-ipv6]` / `[ts-peer-ip]` | 已遮蔽的位址 |
| `[tailnet]` | tailnet DNS 後綴 |
| `[account]` | tailnet 帳號 |
| `[peer]` | 其他 fleet 成員（僅出現於 `tailscale status` 傾印）|

**代號 ↔ 實際節點的對照表不在此 repo**（否則去識別化即失效）；需查對照請見內部私有 repo。
遮蔽同時施加於**證據檔**（`meta/*.meta` 的 `url_effective`、`meta/instance-provenance.txt`、`run.log`），
故其中的 URL 亦以代號呈現 —— **分析結論不受影響**（「node ID 相同 ⇒ 就地升級」等判讀皆保留）。

## 每包的內容

| 檔案／目錄 | 內容 |
|:---|:---|
| `ANALYSIS.md` | **主報告**：逐案例分析 + 跨版本對照 + 發現（每條標嚴重度與「證據/觀察/空轉」級別） |
| `README.md` | 證據地圖 + **可執行複驗指令**（每條都經實跑、輸出與文件一致） |
| `run-test.sh` | runner（第 1–5 輪 sha256 相同；**第 9 輪另有 `meta/run-test-as-executed.sh`**；**第 10 輪另有 `meta/aborted-attempt-runner-efa7f666.sh`** —— 都是「實際執行的那一份」的留存） |
| `run.log` | 完整執行 stdout（含每案例 echo 標籤與完整 response body） |
| `raw/` | **逐位元組** response body（+ `openapi.json` 契約） |
| `headers/` | 每案例完整 HTTP response headers |
| `meta/` | http_code / 耗時 / bytes / **curl 參數** / 節點 provenance |
| `json/` | `raw/` 的 pretty-print 版 |
| `repeat/`（舊）／`probe/`（第 9 輪） | 重現性探針（同查詢 N≥3 次；逾時或 5xx 也是證據）＋定向探針 |
| `probe/` | 定向探針（驗證新欄位語意、端點異常診斷） |
| `supplemental/` | `/personadb/detail` 樣本（維度字典查證） |
| `summary-per-case.csv` | 逐案例彙總（Excel 可開） |
| `summary-per-persona.csv` | 逐 persona 明細 |
| `version-comparison-nway.csv` | 跨版本對照表（**僅第 1–8 輪；第 9 輪起依 skill v2.0.0 不再產出**） |

---

## 怎麼複驗

### 最短路徑：讀主報告

```bash
less qa-reports/round5-v5.6-nodeB-frozenrunner/ANALYSIS.md
```

### 抽驗原始證據（不重跑，零成本）

```bash
cd qa-reports/round5-v5.6-nodeB-frozenrunner
cat raw/07_debt.body | jq .        # 位元組級證據
cat meta/07_debt.meta              # HTTP code / 耗時 / curl 參數
cat headers/07_debt.headers
```

### 第 1–8 輪交叉對照（**歷史材料**；不需重跑，用已保存的證據）

> ⚠️ 依 skill v2.0.0，**第 9 輪起不做跨版本比對**，故此節僅適用第 1–8 輪。

> ⚠️ 以下指令**在 `round6-…/` 目錄內執行**（故用 `../` 指到其他輪）；從 `qa-reports/` 執行請去掉 `../`。

```bash
cd qa-reports/round8-v5.7-nodeB-upstreamrunner
python3 compare-nway.py \
  ../round1-v4.9.2-nodeA \
  ../round2-v5.2-nodeB \
  ../round3-v5.3.1-nodeA \
  ../round4-v5.4-nodeB \
  ../round5-v5.6-nodeB-frozenrunner \
  ../round6-v5.6-nodeB-upstreamrunner \
  ../round7-v5.6-nodeA-upstreamrunner \
  .
# 註 1：會在最後一個目錄（.）寫出 version-comparison-nway.csv
# 註 2：只比較案例 1–8（round6/7/8 多出的案例 9「業主本人」沒有前輪 baseline）
# 註 3：第 7、8 輪的**報告本身不做版本比對**（依指示聚焦 response 分析）；納入本指令僅為技術上可行
```

### 各包自己的複驗指令

每包 `README.md` 內有 10+ 條可執行指令（契約一致性、不變式、探針、跨版本指標等），
**全部經實跑驗證、輸出與文件一致**。

### 重跑整套（⚠️ 需連得到受測節點，約 13–30 分鐘／輪）

```bash
cd qa-reports/round5-v5.6-nodeB-frozenrunner
OUT=/tmp/rerun BASE_URL=http://<node>:8000 bash run-test.sh
```

> ⚠️ **重跑結果必然不同** —— endpoint 為 LLM-backed，實測同一查詢 `total_matched` 變異可達 **62×**。
> 保留本目錄作 baseline 才能做「同查詢不同結果」比對。

---

## 跨輪重要發現（完整版見各包 ANALYSIS.md）

> **⚠️ 本節已於 2026-09-14 依 `CORRECTIONS.md` 全面更正** —— 原始判讀保留在各包 `ANALYSIS.md`（原文不動）。

### 產品缺陷（3 條，皆已修復）✅
- **v5.2**：新增並實際使用 `aesthetic_procedure` / `debt_status`（第 1 輪發現它們不存在）
- **v5.3.1**：`scoring_basis.dims_counted` 低報計分維度 → **不一致數 33 → 11 → 0**
- **v5.6 前後**：錯誤回應違反自身 `ErrorResponse` 宣告（第 4 輪發現）→ **第 6 輪以負向測試驗收修復** ✅

### 契約可觀測性改善（回應本系列建議）
- **v5.4**：新增 `pool_exhausted` / `returned`（回應第 3 輪「回傳數 < top_k 是契約風險」）、
  `score_scale: "relative-within-version"`（回應第 3 輪「分數不可跨版本比較」）
- **v5.6**：`BroadeningAttempt` / `ScoringBasis` **型別化** —— 落實第 4 輪「新欄位只寫在描述裡、codegen 看不到」
- **v5.6**：延遲降至 **98.2s**（前四輪 144–204s）
- **v5.7**：`PersonaSummary` 由 **17 → 24 欄**，新增 `sex`/`marriage`/`education`/`hobby`/
  `region`/`media_diet`/`politics` —— **關閉第 7 輪 §4.5 指出的可觀測性缺口**
  （該輪發現這些維度可出現在 `applied_filters`/`dims_counted` 卻不在 `summary`）。
  回應自此**可自我驗證**：能直接從回傳列確認每個 `applied_filter` 是否生效

### ❌ 我的誤報（3 條，同源）**—— 與產品缺陷數量相同**
| # | 我原本寫的 | 真相 | 出處 |
|:-:|:---|:---|:---|
| 1 | `employment_status` 0/8「橫貫五版的未解問題」，級別「證據」 | **量測工件**：凍結 runner 案例集不含業主語意案例。第 6 輪實測**運作正常** | `CORRECTIONS.md` ③ / issue #51 |
| 2 | 探針 `http=000`「疑似伺服器錯誤處理退步」 | **客戶端／網路路徑**：server log 顯示請求**未達伺服器**、0 錯誤、`restartCount=0` | `CORRECTIONS.md` ② |
| 3 | `opMode` 預設值變更為 **breaking change** | 實為**修復**：舊預設值 `兩者皆可` 不在合法清單內，省略即 **400** | `CORRECTIONS.md` ① / issue #49 |

**共同根因：用症狀歸因，未先取得那一側的證據。** 已寫進 `api-version-sweep` skill
（Step 7 兩段 + 檢查清單 3 項）。**這是本系列最重要的產出。**

### 第 7 輪（`NODE-A` Docker 部署）新增 ✅
- **語意正確性 9/9**：各案例 filter 選擇皆符合題意；`#34` 雙向驗證通過
  （業主 query 套 `employment_status=['雇主']` 且 10/10 回傳皆雇主；顧客 query 正確不套）
- **模型的 `reasoning` 已內化 #34 判準**（明寫「主體是顧客不是業者本人，故不使用 employment_status」）
- **`dims_counted` 的誠實性經「正向實驗」驗證**：以 `top_k=30` 取得更大池子後，找到
  **相同計分向量、不同 `city_price_tier`（高 vs 低）** 的 persona，**分數完全相同**
  ⇒ 居住地／城市層級確實不參與計分 ⇒ 宣告完整
- **推翻一條假設**：先前看似「居住地影響計分」的線索（top-3 全在同一城市）
  **經該實驗否證** —— 若未做探針，就會誤報一條不存在的缺陷

### 第 7 輪新增 ⚠️（觀察，非缺陷）
- **頭部集中 25%**：20 個 top-3 persona 中 5 個跨案例重複，且橫跨不同產業
  （同一 persona 同時是多個不相關 query 的 top-3）⇒ 下游名單會跨題重疊
- **Broadening 空轉 31%**（5/16 輪迴圈 `no_op`）；0 次 `overshoot`
- **TESLA 案例把 `commute_mode` 放寬掉** —— 與模型自述意圖（「以汽車通勤」）不一致
- **同輪、同 query 的 filter 就會不同**：主套件 `debt_status=['無']` vs 同輪 probe
  `['無','有房貸','有信貸或卡債']` ⇒ 再次顯示抽樣變異，且放寬後語意精度下降
- **可觀測性缺口**：`sex`/`marriage`/`education`/`hobby` 可出現在 `dims_counted`
  卻**不在 `summary`** ⇒ 消費端無法從回應驗證其是否生效
- **上游斷言 #42 的絕對門檻**（第 7 輪 §2 發現）→ **已開票 #52、已修復**
  （改比例式 `>=0.9`；上游 sha `9a29a8ef` → `5c1ca716`）

### 方法論修正（2026-09-14，非產品問題）
「同分 ⇔ 同 `dims_counted` 向量」的檢定原本**混用兩種情況**：
**(a) 同分但向量不同**＝**分數碰撞**（合法）；**(b) 同向量但分數不同**＝**dims_counted 低報**（真缺陷）。
區分後重驗：第 1 輪的 33、第 2 輪的 11 **全屬 (b)**（原結論正確）；
但**第 5 輪報告的「1」實為 (a) 碰撞** —— 該輪 `dims_counted` 其實是完美的。
另：該檢定僅能涵蓋 `summary` 曝露的維度（見上「可觀測性缺口」）。

### 第 8 輪（`NODE-B` **v5.7**）✅
- **上游斷言 13/13 全數通過**（含負向測試 #47）；`#42` 的比例式修復**已驗證生效**，
  輸出同時給出比例與 `pool_exhausted`，可讀性提升
- **語意正確性 9/9**；醫美案例**現在有 `sex=['女']` 硬篩選**（先前僅 `aesthetic_procedure`）
- **回應「自證性」實測通過**：24 欄 summary 下，9 項可驗證查核（sex/marriage/education/
  employment_status/debt_status/aesthetic_procedure）**全部在回傳列中被滿足**；
  7 個新欄位在全部 66 筆皆為實值（`hobby` 為多值陣列）
- **計分宣告誠實**：具檢定效力的 5 個案例中，低報 **(b) = 0**

### 第 8 輪新增 ⚠️（觀察）
- **Broadening 空轉率 60%**（9/15，較先前明顯偏高）。最嚴重為案例 4：
  **三輪放寬全部無效**（`13→13` ×3），且第 1 輪聲稱「新增教育、醫療、其他」
  —— **該三值本來就已在 `applied_filters` 中**；第 2/3 輪反覆調整 `housing_cost`
  卻證明它並非約束 ⇒ **放寬機制挑錯維度**
- **首次觸發 `overshoot`**：案例 2（TESLA）移除 `commute_mode` 使樣本 `19→60`（**3.2×**）。
  但「以汽車通勤」對電動車是核心語意維度，模型自己的 reasoning 也如此陳述
  ⇒ **自述意圖與放寬行為矛盾**（v5.6 已見同一模式，本輪能量化）
- **頭部集中 19%**：21 個 top-3 persona 中 4 個跨案例重複（含同時是兩題 top-1 者）
- **案例 6 延遲離群 588.9s**（次慢者 292.9s）—— **未歸因**（未取得伺服器端證據）
- **版本落差**：部署服務自報 **v5.7**，repo `RELEASE-VERSION` 為 **v5.6**。
  上游 `#50` 正是檢查此事，惟需 host 權限 → 遠端 runner **N/A**，**無法判定**

### 第 9 輪（`NODE-A` **v5.8**）✅
> 本輪依 skill **v2.1.0** 執行：**只分析 v5.8 的回應，不做跨版本比對**。以下為該輪自身的發現。

- **斷言 31 ✅ / 1 ⚠️ / 0 ❌ / 0 N/A**。**首次在節點本機執行**（`localhost`），因此主機層斷言
  `#50`（部署版本 == `RELEASE-VERSION`、含 `finish_reason` 診斷碼）與 `#55`（例外型別診斷碼）
  **原生執行、無任何 N/A** —— 補上了第 8 輪只能標 N/A 的那一項
- **部署保真度以 byte 級證明**：release tarball sha256 與節點上同一檔相同；
  `/srv/persona-db-data/api/*.py` 與 tarball 內 `api/*.py` **8/8 檔 sha256 相同**；
  容器 `/app` 為該目錄的 **bind mount** ⇒ 執行中的程式碼 == 發佈的 v5.8 產物
- **可觀測性缺口為 0**：`summary` 24 欄全數曝露，本輪所有 `applied_filters`／`dims_counted`
  維度**全部**可從回應自我驗證（15/15 項通過）
- **計分宣告誠實**：9 個具檢定效力的配對中，低報 **(b) = 0**
- **`#47`–`#49`、`#53`、`#56` 全部 ✅**；本輪額外觸發 **503**，錯誤同樣走統一的 `ErrorResponse` 形狀
  （把 `#47` 的涵蓋從 400 延伸到 503）
- **資料不足時不編造**：`matched=0` 時回 `returned=0`；語意無法解析時回 503 而非隨機名單
- **新欄位 `broadening_stop_reason` 與「連續空轉 ≤2」有效**：10 輪放寬中 `no_op` 僅 1 輪（10%），
  且 `no_op`／`overshoot` 旗標與 `match_count_before/after` **10/10 一致**（此一致性 upstream 未驗）

### 第 9 輪新增 ⚠️
- **放寬步驟會移除「分析步驟自己說必須用」的維度**（5/9 案例）。最尖銳者為案例 07（債務整合）：
  **同一案例的相鄰兩輪自我矛盾** —— loop1 稱 `debt_status`「為本題核心條件…**不可放寬**」，
  loop2 卻「**移除** `debt_status`…該維度非核心」⇒ `8→58`（7.25×、`overshoot=True`），
  回傳第 9、10 名為 `debt_status='無'`（分數把它們壓在 4.54/4.48，前 8 名為 5.07–5.38）。
  **`#42` 斷言正確地發 ⚠️**（`保留=False 符合率=8/10`）—— 是護欄在做事，不是誤報
- **兩個案例的重跑結果不可重現**：案例 06 四次執行得到**四種**結果（`total_matched` 9–16、
  套用維度 **1→5 個**、停止原因在 `no_op_limit`/`loop_limit` 間跳）；案例 09 的 `total_matched`
  為 **20 ↔ 61（3×）**（惟 `employment_status` 4/4 都套用 ⇒ must-use 的結論**是**可重現的）
- **`status='ok'` 伴隨 `returned=0`**：兩次定向探針都回 0 筆卻報 `ok`（`too_strict` 需跑滿 3 輪才觸發）
- **503 的指引文字會誤導維運**：`message`/`details` 指向「LLM 分析失敗／檢查 API key」，
  但 server log 顯示 **LLM 呼叫成功、只是產不出 filter**（`LLM returned no filters`）
- **契約宣告了不可達的停止原因**（源碼層推論）：`""` 與 `budget_limit` 在現行常數下不會出現

### 第 9 輪的方法論新增（已回寫 skill v2.1.0）
- **要驗「執行時行為」，不能只驗「腳本字面」**：本輪的儀器忠實度檢查（比對腳本內容）全數通過，
  但 runner 執行時把案例標題印成了 tmpname —— 因為我的 helper 參數位移錯誤。已補
  `meta/test-runner-harness.sh`（stub `curl`、11 項）把「執行時印出什麼」變成可驗證的
- **背景 watcher 不可用 `pgrep -f "<script>"`**：會 match 到 watcher 自己的 cmdline 而永不結束；
  改用完成標記檔
- **「執行時的那一份 runner」必須另存**：本輪在執行後才修 helper，故 `run-test.sh` 已非產出證據的
  那一份；已另存 `meta/run-test-as-executed.sh`（`1557c38e…`）並證明**兩份**的請求參數與斷言段
  都與 upstream 逐字相同

### 第 10 輪（`NODE-A` **v5.10**）✅
> 依 skill **v2.1.0**：只分析 v5.10 的回應，**不做跨版本比對**。以下為該輪自身的發現。

- **斷言 42 ✅ / 0 ⚠️ / 0 ❌ / 0 N/A**（新增 `#57` 核心維度保護、`#58` `status` 語意、`#59` enum、
  `#60` root logger、`#61` `commute_mode` 保護）
- **部署保真度以 byte 級證明**：release tarball sha256 與節點上同一檔相同；
  `/srv/persona-db-data/api/*.py` 與 tarball 內 `api/*.py` **8/8 檔 sha256 相同**；
  容器 `/app` 為該目錄的 **bind mount** ⇒ 執行中的程式碼 == 發佈的 v5.10 產物
- **核心維度保護機制經重跑驗證有效**：兩個被探針的案例各 4 次執行，
  **`protected ∩ relaxed = ∅` 4/4 成立**、**核心維度認定 4/4 一致**；
  第九輪「把 `debt_status` 放寬掉、`8→58` overshoot」**4/4 未再出現**；`#42` 由 ⚠️ 轉 ✅；
  `#61` 的 TESLA `commute_mode` 也受保護且未被放寬
- **硬性 veto 有牙齒**：定向探針逼出模型試圖移除受保護的 `employment_status` →
  系統**還原該輪並以 `protected_veto` 停止**（`vetoed_dims=['employment_status']`）。
  額外驗證了 upstream 未驗的不變式：`vetoed_dims ⊆ protected_dims`、veto 必有非空 `vetoed_dims`、
  且 veto 確實是一次 rollback（`no_op=True`、`filters_changed=False`、計數不變）
- **`status` 語意修正**：`matched==0 ⇔ status!='ok'` 在 **18/18 筆**（含 3 筆空池）成立
- **放寬行為收斂**：10 輪放寬中 **`no_op` 0 輪、`overshoot` 0 輪**；
  自述與實作的矛盾 **0 件**（第九輪同型態有 5/9）；`no_op`/`overshoot` 旗標與數字 **10/10 一致**
- **可觀測性缺口 0**（13/13 自證通過）、計分低報 **(b) = 0**（並出現 3 個合法的 (a) 同分碰撞）

### 第 10 輪新增 ⚠️
- **同一 query 的 `matched` 變異仍極大**：案例 07（債務整合）四次執行得到 **0 ↔ 30**；
  案例 06（醫美）為 14–16。**單次 sweep 的數字不可作為品質結論**
- **「值集放寬」沒有護欄、也不留痕**：案例 06 的 loop2 把 `sex` 由 `['女']` 放寬為 `['女','男']`，
  而同案例 reasoning 說「以女性為主」。因為是值集放寬而非移除維度，**不進 `relaxed_dims`**，
  任何檢查都看不到（該輪回傳 10 筆恰好全為女性，實務後果為零）
- **`applied_filters` 可出現空值清單，等同「排除全部」**：部署碼 `filter_personas()` 對字串型維度做
  `if val not in accepted`，`accepted == []` 時**恆為真**。這解釋了探針 `r07_debt_1` 的
  `loop2: 6→0` 與最終 `matched=0`。觀測到 1/18 筆，無機制阻止
- **`broadening_stop_reason` 仍宣告 2 個不可達的值**（`""` 與 `budget_limit`）—— 源碼層推論，
  在 v5.10 重新驗證仍成立
- 案例 08（小吃攤）的 `protected_dims` 為**空**（該題若需放寬，沒有任何維度受保護）

### 第 10 輪的作業疏失（已記錄於該包 `meta/known-defects.txt`）
- 第一次啟動時，runner 因**寫死 `OUT="$HOME/qa-round9"`**（複製上一輪工具時忘了改），
  把 v5.10 的證據寫進了**第九輪在節點上的工作副本**（7 檔被覆寫）。
  **本機 master 與已發布的第九輪均未受影響**（以 sha256 逐項驗證）。
  該節點目錄已更名隔離為 `qa-round9-POLLUTED-by-round10-attempt`；
  中止那次的 runner 保留為 `meta/aborted-attempt-runner-efa7f666.sh`；
  `make-runner.py` 已改為**由目錄名推導 `OUT`** 並加三道殘留檢查。

### 第 11 輪（`NODE-A` **v5.11.1**）✅
> 依 skill **v2.2.0**：只分析 v5.11.1 的回應，**不做跨版本比對**。以下為該輪自身的發現。

- **斷言 44 ✅ / 1 ⚠️ / 0 ❌ / 0 N/A**（新增 `#62` 空值清單守門、`#63` 值集放寬留痕、
  `#57` 的 K/L/M veto 不變式、`#56` 白名單動態化）
- **第十輪的三條建議都已落地，本輪逐項驗證有效**：
  ① 值集放寬有了留痕欄位 **`widened_dims`**（3 輪有痕跡；本輪另加驗 `widened ⊆ applied ∪ relaxed`）
  ② 空值清單有了守門（`#62` 斷言 + `_normalize_filters` 修復）
  ③ 上游把我第十輪提出的 **K/L/M veto 不變式採納為出貨斷言**（原始碼註解明載來源）
- **核心維度保護在重跑下穩定**：案例 06／07 各 4 次執行，**`protected ∩ relaxed = ∅` 8/8 成立**、
  **核心維度認定 8/8 一致**、`debt_status` 套用值 4/4 正確
- **兩個真實 veto 事件**（定向探針逼出）：模型要移除受保護的 `employment_status`／`family_income`
  → 系統**還原該輪並停止**，K/L/M 三條不變式全數成立
- **`#56` 白名單動態化生效**（以 OpenAPI enum 為準），消滅了硬編清單隨版本腐化的問題
- 計分低報 **(b) = 0**（15 個具檢定效力的配對）；可觀測性缺口 0

### 第 11 輪新增 ⚠️（本輪最重要）

- **「小吃攤老闆的目標客群（顧客語意）」會隨機落到兩種相反詮釋 —— 4 次執行中 2 次反轉。**
  反轉時模型自述「需鎖定小吃攤老闆本人…而不是他們的顧客」，回傳的是**高收入製造／服務業雇主**
  （`matched` 11–61）；正確時是中低消費力消費者（`matched` 101–111）。
  **反轉那次的名單與 case09（B2B 業主本人）重疊 9/10（90%）**。
  兩個模式都回 `status='ok'` —— **回應本身不會警示這次是顧客還是業主的詮釋**。
  > ⚠️ 本輪主套件那次**剛好是反轉的那一半**。這不是穩定缺陷，是**不可預測的判準漂移**，
  > 比穩定缺陷更難防；`#34` 斷言正確地發了 ⚠️（測試期才發現，執行期無防護）。
- **`protected_dims` 會連「被誤套的維度」一起保護**：反轉時 `employment_status` 被列入保護集，
  後續若有放寬需求時該錯誤更難被自動修正。
- **`#62` 修復沒有留痕**（`_normalize_filters()` 不寫 log）⇒ 無法從 log 判斷修復是否觸發過；
  本輪只能說「沒有觀察到違規」，**不能說「已驗證修復有效」**。
- **同一題的 `matched` 變異仍極大**（案例 08：11 ↔ 111 = 10×；案例 07：19 ↔ 43）。

### 第 11 輪的方法論新增（將回寫 skill）
- **檢查「跨輪聚合欄位」時，要驗同一輪內的一致性，而不是案例層級的集合交集**：
  本輪我的 `widened_dims ⊆ applied_filters` 檢查在一個案例上報了假違反，
  追查後是**合法的跨輪序列**（loop1 放寬值集 → loop3 因該維度已無篩選效果而移除）。
- **跨輪複製工具的路徑要「自我定位」**：上一輪的教訓（由目錄名推導）本輪再升級為
  `OUT="$(cd "$(dirname "$0")" && pwd)"`；且**檢查必須涵蓋 probe 腳本等所有複製過來的工具**
  —— 本輪開跑前的檢查當場抓到 `run-probe.sh` 仍寫死上一輪的 `OUT`。

### 第 12 輪（`NODE-A` **v5.12**）✅
> 依 skill **v2.4.0**：只分析 v5.12 的回應，**不做跨版本比對**。以下為該輪自身的發現。

- **斷言 53 ✅ / 0 ⚠️ / 0 ❌ / 1 ℹ️**（新增 `#65` 主體護欄：`subject` + 禁用維度剝除 + `warnings`）
- **`#65` 主體護欄把第十一輪的雙峰收斂了**：小吃攤（顧客語意）在主套件 + 3 次重跑
  **4/4 都是 `subject='customer'`**、`employment_status` 4/4 未被套用，名單回到中低消費力消費者
  （`matched` 45–153）。同質化矩陣顯示**沒有任何 ≥8/10 的配對**（第十一輪是 9/10）。
- **護欄是執行期機制且可稽核**：伺服器端有 `Subject gate (#65): subject=… forbidden=…` 的 INFO 行，
  回應裡也有 `subject` 欄位供消費端辨識本次詮釋方向
- 核心維度保護穩定（案例 06 `aesthetic_procedure` 4/4 受保護）；兩次 veto
  （`vetoed_dims=['employment_status']`、**首次出現的 `['marriage']`**）皆符合 K/L/M
- 放寬乾淨：12 輪中 `no_op` 1 輪、`overshoot` 0 輪、旗標與數字 12/12 一致；值集放寬 4 輪有留痕
- 契約、錯誤處理、可觀測性乾淨：無 verifiability gap、計分低報 (b)=0

### 第 12 輪新增 ⚠️

- **`#65` 的「剝除 + `warnings`」路徑完全沒有被行使**：19 筆回應 `warnings` 全空、
  伺服器端剝除次數 **0**（護欄生效時 LLM 本來就沒套用被禁維度）⇒ 那條路徑目前是
  **「宣告了但沒走過」**，要驗它需要**不依賴 LLM** 的單元／整合測試。
- **本輪被採納的 S/T 不變式用的是過嚴形式**（`widened_dims ⊆ applied_filters`、
  `widened ∩ relaxed = ∅`），會對**合法的跨輪序列**假警報。本輪新實例：`05_role_banker`
  的 loop2 **放寬 `income` 值集** → loop3 **整維移除 `income`** ⇒ 嚴格 S/T 都會報 ❌，
  但那是合法行為（放寬後該維度失去篩選效果）。正確形式是 `widened ⊆ applied ∪ relaxed`。
  > ⚠️ 它**之所以沒報錯，是因為只掃 4/9 案例**（`_cases` 只含醫美／債務／業主／小吃攤），
  > 而 `05_role_banker` 不在其中。對全部 19 筆重算，只有這 1 筆會誤報。
- **`subject` 只在 2/9 案例判定出來**（08 `customer`、09 `owner`；其餘 7 題為 `''` 不設限）
  ⇒ 護欄的保護面只覆蓋少數題型。
- **護欄固定的是「詮釋」，不是「抽樣」**：同一題 `matched` 仍在 45↔153（3.4×）之間變動。

### 第 12 輪的方法論新增（已回寫 skill v2.5.0）
- **「建議被採納時，讀者只會讀那張表」**：第十一輪把 S/T 寫進「我額外加驗」表格時還是過嚴形式，
  更正卻寫在後面的限制章節 ⇒ 新版照表格採納。**不變式的最終正確形式必須寫在提出它的那張表裡。**
- **「斷言通過」要附「它實際檢查了幾個案例」**：S/T 沒報錯不是因為沒有違反，
  而是因為只掃 4/9 案例 —— 把 §6.3 既有的「具檢定效力的案例數」紀律推廣到所有斷言。

### 仍未解 ⚠️（經更正後仍成立）
- **ranking 層不可重現**：版本內 top-3 交集多為 0–1/3。第 5↔6 輪同版本對照顯示抽樣變異可達 **5×**
- **分數尺度跨版本漂移**（案例 04：v5.4 `4.86` → v5.6 `2.54`）⇒ 有絕對分數門檻的下游邏輯升級會失效

### 值得注意的事件
- **v5.4**：HTTP 503 `FILTER_FAILED`（該回應的 schema 不符問題已於後續修復，見上）
- **v5.6**：重現性探針首次執行 3/3 於精確 **75.00s 硬切、無 HTTP 回應** → transient；
  真因在客戶端／網路路徑（已由 server log 否證伺服器端）
- **v5.6**：`opMode` 預設值 `兩者皆可` → `僅篩選`（**修復 400**，非 breaking；見上表 #3）

---

## 儀器忠實度

- 上游腳本 sha256：`33749d4e5218f3860f15f4296c5fc5ea90f0fa93f441bc4eba9faf2274dad2e3`
- 改寫後 runner sha256：`ffc7b10642f72f4120a43b77848ed722c6cf865c23b3267a3eb87bd48c74695d`（**五輪相同**）
- 相對原腳本的改動**只有三項**（base URL、證據落盤、diff check 解析工具），
  **請求參數／順序／斷言邏輯 100% 未變**。詳見各包 `ANALYSIS.md` §8。

**第 9 輪（v5.8）的儀器**（上游腳本已改版，故與上述數字不同）：
- 上游腳本 sha256：`e6c6fe7797a21600e6ec9f7f769e2ab80462d11374996986a16335772bddc677`（**301 行**）
- **實際執行的 runner**：`1557c38eb85215c16a6a4ea4209eae52da3a6395a731eff5e41eb4c554b2ef64`
  = `meta/run-test-as-executed.sh`（該輪執行後才修 helper，故此檔必須另存）
- 忠實度以 `meta/verify-instrument.py` 機械證明：**請求參數 32/32 相同且順序一致**、
  斷言段 `L88–L301` **逐字相同（0 差異）**、案例標籤 9/9 相同；改動逐條列於該輪 `ANALYSIS.md` §7

**第 10 輪（v5.10）的儀器**（上游腳本再次改版）：
- 上游腳本 sha256：`f57392bb9d35f0a2351ea96d67b3e7b2cd1a7af7f0d7916ad573a4b10c99eb0`（**372 行**）
- runner sha256：`985fdb8198c08500354555a6223cdfc04e498743568bde7a9defa5c2cce4c068`
  （**執行前即記錄**）；另留存中止那次啟動的 runner `meta/aborted-attempt-runner-efa7f666.sh`
- 忠實度以 `meta/verify-instrument.py` 機械證明：**請求參數 32/32 相同且順序一致**、
  斷言段 `L88–L372` **逐字相同（0 差異）**、案例標籤 9/9 相同；
  另以 `meta/test-runner-harness.sh`（stub `curl`、11 項）驗「**執行時行為**」

**第 11 輪（v5.11.1）的儀器**：
- 上游腳本 sha256：`f3cb96adc76aff3a01bee390c40bf3a0f4c3c39bf2ce344850b278a19cfbe28b`（**421 行**）
- runner sha256：`ef6c0f36786937db29fddf4ee723815834bee6bb30a4655e6898d76675cec40a`（執行前即記錄）
- 忠實度：**請求參數 32/32 相同且順序一致**、斷言段 `L88–L421` **逐字相同（0 差異）**、
  案例標籤 9/9 相同；另以 `meta/test-runner-harness.sh`（11 項）驗執行時行為
- **跨輪防護**：runner 與 probe 的 `OUT` 皆改為 **自我定位**（`dirname $0`）；
  開跑前的殘留檢查抓到兩處舊輪次路徑並修正

**第 12 輪（v5.12）的儀器**：
- 上游腳本 sha256：`2070ad91f45cbcef20648ee6662a4d667f95b82599f6a6969acac7be80e56dfb`（**480 行**）
- runner sha256：`350e16a4253341c7b9859c73a9692bf4bbe9e833e8416aa64891fc7edacf1fb7`（執行前即記錄）
- 忠實度：**請求參數 32/32 相同且順序一致**、斷言段 `L88–L480` **逐字相同（0 差異）**、標籤 9/9 相同
- v5.12 改了時尚案例的輸出路徑（CWD → `/tmp`），runner 隨之**取消特例分支**改走同一條落盤路徑
- **探針題目原文已寫進報告與 README**（skill v2.4.0 起的新規定）

## 已知限制

- **去識別化只涵蓋現行檔案，不含 git 歷史**：`git log -p` 仍可取得遮蔽前的原始值。
  **✅ 已決策（2026-09-14，kstsai）：接受此狀態，不改寫歷史。**
  理由：歷史改寫（`git filter-repo` + force push）為破壞性操作，且風險大於此處的暴露程度
  （遮蔽目標主要為 tailscale CGNAT 位址，需 tailnet 成員身分才有意義）。
  → **請勿再提議或執行歷史改寫**；若日後確實需要，須由 kstsai 明確指示。
- 遮蔽後 `meta/*.meta` 的 `url_effective` 以代號呈現，**與當時實際請求字串已不同**；
  重跑請以各包 `README.md` 的 `BASE_URL` 參數帶入實際位址。

## 誠實聲明

- 除案例 01 有 3–4 次取樣，其餘案例每輪僅 **1 次**執行；**已知 LLM 雜訊大，單次差異不可歸因於版本**。
  各報告中已逐處標示該條屬「證據」「觀察」或「空轉」。
- 五輪橫跨兩台機器（`NODE-A` 與 `NODE-B`，公網 IP 同為 `[public-ip]`），
  **延遲比較受硬體／網路影響，只當參考**。
- 第 3 輪報告的「收入桶完全飽和案例數」初稿有計算錯誤（寫 5/8、4/8，實為 **7/8、5/8**），
  已於 2026-09-13 更正並在檔內註明。
