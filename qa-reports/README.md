# LLM Verify QA Reports — persona-db API 跨版本實測

> **同一份測試腳本**（`upDockerVerHermes/test-persona-db-api.sh`）對**多個版本／節點**重複執行，
> 逐案例保存 **byte 級證據**，產出可交叉比對的跨版本報告。
>
> 方法論：`api-version-sweep` skill（dsh 系共用 kit）。
> 執行者：dsh1（DeepSeek Harness）。**五輪的 runner sha256 完全相同** ⇒ 跨輪可比。

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

## 七輪一覽

| # | 版本 | 節點 | runner | 日期 | 契約 sha256(16) | 結果 | 該輪重點 |
|:-:|:-----|:-----|:-----|:-----|:----------------|:-----|:---------|
| 1 | **v4.9.2** | `NODE-A` | 凍結 90 行 | 2026-09-12 | `8ac54b95228d85fc` | 9/9 | 基線。發現 `aesthetic_procedure`/`debt_status`/`employment_status` **不存在** |
| 2 | **v5.2** | `NODE-B` | 凍結 | 2026-09-12 | `8b869ae266992056` | 9/9 | **+3 維度**（25 維）並投入運作；樣本變異達 **62×** |
| 3 | **v5.3.1** | `NODE-A` | 凍結 | 2026-09-12 | `8b869ae266992056` | 9/9 | 純行為 patch（契約同 v5.2）；`dims_counted` 修正為 0 不一致 |
| 4 | **v5.4** | `NODE-B` | 凍結 | 2026-09-12 | `30a228782154bdce` | **8/9** | +`pool_exhausted`/`returned`/`no_op`/`overshoot`/`score_scale`；首見 503 且**該回應違反自身宣告 schema** |
| 5 | **v5.6** | `NODE-B` | 凍結 | 2026-09-13 | `aafe647f46ee8abe` | 9/9 | **契約型別化**（落實第 4 輪建議）；延遲 98.2s |
| 6 | **v5.6** | `NODE-B` | **upstream 223 行** | 2026-09-14 | `aafe647f46ee8abe` | **10/10** | **結案 issue #51**（`employment_status` 實為量測工件）；負向測試**驗收 #47 已修復** |
| 7 | **v5.6** | `NODE-A` | upstream 223 行 | 2026-09-14 | `aafe647f46ee8abe` | **10/10** | **主機端驗收**（Docker 部署）：語意正確性 9/9；**判讀不跨版本比對**，聚焦 response 內容分析 |

**共 4 種不同契約**（v5.2 與 v5.3.1 同 hash ⇒ 純行為 patch；第 5、6 輪同為最後一種）。

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
└── round7-v5.6-nodeA-upstreamrunner/      ← 第 7 輪（同 runner，`NODE-A` Docker 部署；**不做版本比對**）
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
| `NODE-A` | 第一／三輪的受測節點 |
| `NODE-B` | 第二／四／五輪的受測節點（同一節點三次就地升級）|
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
less qa-reports/round5-v5.6-nodeB-frozenrunner/ANALYSIS.md
```

### 抽驗原始證據（不重跑，零成本）

```bash
cd qa-reports/round5-v5.6-nodeB-frozenrunner
cat raw/07_debt.body | jq .        # 位元組級證據
cat meta/07_debt.meta              # HTTP code / 耗時 / curl 參數
cat headers/07_debt.headers
```

### 七輪交叉對照（不需重跑，用已保存的證據）

> ⚠️ 以下指令**在 `round6-…/` 目錄內執行**（故用 `../` 指到其他輪）；從 `qa-reports/` 執行請去掉 `../`。

```bash
cd qa-reports/round7-v5.6-nodeA-upstreamrunner
python3 compare-nway.py \
  ../round1-v4.9.2-nodeA \
  ../round2-v5.2-nodeB \
  ../round3-v5.3.1-nodeA \
  ../round4-v5.4-nodeB \
  ../round5-v5.6-nodeB-frozenrunner \
  ../round6-v5.6-nodeB-upstreamrunner \
  .
# 註 1：會在最後一個目錄（.）寫出 version-comparison-nway.csv
# 註 2：只比較案例 1–8（round6/7 多出的案例 9「業主本人」沒有前輪 baseline）
# 註 3：第 7 輪的**報告本身不做版本比對**（依指示聚焦 response 分析）；納入本指令僅為技術上可行
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
