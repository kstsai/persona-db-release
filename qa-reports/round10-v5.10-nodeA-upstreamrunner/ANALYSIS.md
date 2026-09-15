# Persona DB API 實測分析報告 — v5.10（NODE-A / upstream runner）

> **範圍聲明**：本報告**只分析 v5.10 這個版本的回應**。依 `api-version-sweep` skill
> **v2.1.0**（2026-09-14 依 kstsai 指示取消跨版本比對），**本報告不含任何「與前版對照」的段落**。
> 若某條判讀是對我自己先前報告的更正，會標明「更正」，那不算比對。
>
> 執行時間（UTC）：2026-09-15 **03:34:16 → 03:53:01**（主套件，18 分 45 秒）；探針隨後執行。
> 證據包：本目錄（`raw/` `headers/` `meta/` `json/` `extra/` `probe/`）。

---

## 0. 目標與環境

| 項目 | 值 |
|:--|:--|
| 節點 | `NODE-A`（tailscale `[tailnet]`；內部 hostname 見去識別化約定） |
| 部署型態 | Docker：`hermes` + `persona-db-api` 兩個容器 |
| repo `RELEASE-VERSION` | `v5.10` |
| 服務自報版本（`/personadb/status`） | `v5.10`；容器內 `/app/VERSION` = `v5.10` |
| **執行位置** | **節點本機**（`BASE_URL=http://localhost:8000`，與 upstream 原生環境相同） |
| 容器狀態 | `Up (healthy)`、`restarts=0`、started `2026-09-15T02:25:56Z` |
| 參照副本 | `persona-db-release` HEAD `286ad849fd689e3736447ec5cd17951501639217`（== `origin/main`）；節點上的 clone 同一 sha；取得於 `2026-09-15T03:30Z` |

### 0.1 部署保真度 —— 「裝的到底是什麼」的機械證明

**版本字串不算證據**，所以逐層比對到 byte：

| 層 | 檢查 | 結果 |
|:--|:--|:--|
| 交付物 | repo 的 `persona-db-rel-v5.10.tar.gz` sha256 = `22ae9c04099c105e…`；節點上同一檔 sha256 | **相同** ✅ |
| 落盤檔 | `/srv/persona-db-data/api/*.py` 對 tarball 內 `api/*.py` | **8/8 檔 sha256 相同** ✅ |
| 容器 | `/app` 是 `/srv/persona-db-data` 的 **bind mount**；容器內 `/app/api/*.py` sha256 亦同 | ✅ |
| 映像 | `persona-db-api:latest` = `6504bbea0208`，built `2026-09-15T02:20:32Z` | — |
| 斷言 | `#50` 主機層：`部署版本 == RELEASE-VERSION (v5.10)` | ✅ |

→ **執行中的服務程式碼 == 發佈的 v5.10 產物**（byte 級）。

### 0.2 兩點處置說明

1. **我沒有重新部署。** 受測節點在我開始前已是 v5.10（映像 build `02:20:32Z`、容器起於 `02:25:56Z`，我的探測起於 `03:30Z`）。既然上面已證明部署 == 發佈產物，重新部署會是同義重複，且會在驗證途中重啟服務。
2. **在節點本機執行**（非從我的機器跨 tailnet）。理由：① `#50`／`#55`／`#60` 等主機層斷言可原生執行（`sudo` 免密碼），本輪因此**沒有任何斷言被標 N/A**；② 移除「我的機器 ↔ 節點」這段網路的變數。

> 依 `qa-reports/CORRECTIONS.md` **修正④**，此處已記錄參照副本的 commit sha 與取得時間；本輪部署版本與 repo `RELEASE-VERSION` **一致**，無版本落差。

---

## 1. 儀器

| 項目 | 值 |
|:--|:--|
| upstream | `upDockerVerHermes/test-persona-db-api.sh` |
| sha256 | `f57392bb9d35f0a2351ea96d67b3e7b2cd1a7af7f0d7916ad573a4b10c99eb0` |
| 行數 | **372**（v5.8 時為 301；新版含 #57/#58/#59/#60/#61 斷言） |
| 來源 | `https://raw.githubusercontent.com/kstsai/persona-db-release/main/upDockerVerHermes/test-persona-db-api.sh` |
| 取得時間（UTC） | 2026-09-15T03:30Z |
| **runner sha256（執行前記錄）** | `985fdb8198c08500354555a6223cdfc04e498743568bde7a9defa5c2cce4c068`（368 行） |
| 原版留存 | `meta/original-upstream-f57392bb.sh`（逐字原檔） |

### 1.1 「不可改的沒被改」—— 機械證明

`meta/verify-instrument.py` 的輸出（可重跑）：

```
[1] 請求參數／順序  upstream=32 runner=32  ✅ 相同（含順序）
[2] 前段 L1-L14     ✅ 逐字相同
[3] 斷言段 L88-L372 ✅ 逐字相同（0 差異）
[4] 案例標籤 9/9    ✅ 逐案相同
```

作法：前段與斷言段以**原檔逐字切片**併入 runner（不經人手轉錄）；案例標籤**直接從 upstream 的 `echo` 行抽取原文**。

另依 skill v2.1.0 的新紀律，執行前先跑了 **`meta/test-runner-harness.sh`**（stub `curl`、不連網、11 項）
驗證「**執行時行為**」—— 本輪**沒有**重演第九輪「標題印成 tmpname」的錯。

**長跑的等待方式**：主套件用 **`RUN_DONE` 完成標記檔**、探針用 **`PROBE_DONE`**
（`probe/run-probe.sh` 最後一行 `touch "$P/PROBE_DONE"`），
**沒有**使用 `pgrep -f "<script>"` —— 那會 match 到 watcher 自己的 command line 而永不結束（skill v2.1.0 Pitfall）。

### 1.2 本包證據的已知缺陷（必讀）

- **缺陷 1（嚴重，已完成處置）**：我第一次啟動時，runner 因為**寫死 `OUT="$HOME/qa-round9"`**（我複製第九輪工具時忘了改），把 v5.10 的證據寫進了**第九輪在節點上的工作副本**（7 檔被覆寫）。**本機 master 與已發布的第九輪均未受影響**（逐項以 sha256 驗證過）。已修法為「由本輪目錄名推導 OUT」+ 三道殘留檢查，並把該節點目錄更名為 `qa-round9-POLLUTED-by-round10-attempt`。
- **缺陷 2**：診斷期間曾同時有兩個 runner 實例（第一次啟動「看起來沒動」時我又跑了一次前景診斷）。兩者都未走完任何案例，**沒有產出被誤用的證據**。
- **缺陷 3**：探針腳本在我重建目錄時被我刪掉、忘了重新上傳，導致探針延後約 2 分鐘才啟動（不影響任何已取得的資料）。

完整影響範圍與確認方式見 **`meta/known-defects.txt`**。

---

## 2. 執行摘要

| # | 案例 | HTTP | 耗時(s) | bytes | top_k | matched | returned | 輪數 | 停止原因 | protected |
|:--|:--|:--:|--:|--:|--:|--:|--:|--:|:--|:--|
| 0 | `/personadb/status` | 200 | 0.9 | 792 | — | — | — | — | — | — |
| 1 | 康是美的目標客戶 | 200 | 62.7 | 3,812 | 3 | 27 | 3 | 0 | `target_reached` | `['clothing_spend']` |
| 2 | TESLA的目標客戶 | 200 | 65.4 | 3,658 | 3 | 25 | 3 | 1 | `target_reached` | `['commute_mode','family_income','income']` |
| 3 | 時尚服裝設計師的目標客戶 | 200 | 142.0 | 7,545 | 10 | 166 | 10 | 0 | `target_reached` | `['clothing_spend']` |
| 4 | 房貸優惠 — 房仲業者 | 200 | 124.4 | 5,045 | 5 | 20 | 5 | 1 | `target_reached` | `['family_size','housing_burden']` |
| 5 | 房貸優惠 — 銀行業者 | 200 | 197.9 | 5,872 | 5 | **14** | 5 | 3 | `loop_limit` | `['debt_status','family_income','housing_burden','housing_cost','income']` |
| 6 | 醫美診所的目標客戶 | 200 | 226.6 | 8,596 | 10 | **14** | 10 | 3 | `loop_limit` | `['aesthetic_procedure']` |
| 7 | 債務整合的目標客戶 | 200 | 150.9 | 8,714 | 10 | 30 | 10 | 3 | `target_reached` | `['debt_status']` |
| 8 | 小吃攤老闆的目標客群 | 200 | 121.9 | 7,693 | 10 | 115 | 10 | 0 | `target_reached` | `[]` |
| 9 | 業主本人（B2B 受訪者） | 200 | 31.7 | 7,515 | 10 | 48 | 10 | 0 | `target_reached` | `['employment_status']` |

- **10/10 HTTP 200**（另含 1 次刻意的負向測試 400）
- 9 個候選案例合計 **1,123.5s**，平均 **124.8s**，最快 **31.7s**（案例 9）、最慢 **226.6s**（案例 6）
- 全套 wall time **18 分 45 秒**
- **伺服器端窗口內 0 次 retry／0 次例外／0 次 WARNING**；`Protected dims` INFO 行 9 筆、`Broadening loop` 17 筆（見 §3 `#60`）
- 兩個案例（5、6）的 `matched=14` 未達 `TARGET_MIN=20`，其餘皆達標

---

## 3. 斷言結果

**合計：42 ✅ / 0 ⚠️ / 0 ❌ / 0 N/A**（完整輸出：`extra/assertions.txt`）

> **0 N/A** 是因為主機層斷言（`#50`/`#55`/`#60`）在節點上原生執行。

| 群組 | 結果 |
|:--|:--|
| `#34` 業主/顧客語意 | ✅ 業主 query 套用、顧客 query 未誤套 |
| `#35` `dims_counted` 涵蓋 `applied_filters` | ✅ 4/4 |
| `#36` 醫美 vs 藥妝語意分流 | ✅ 藥妝未誤套、醫美正確套用 |
| `#37/#42` 每筆放寬都有 `no_op`+`overshoot` 欄位 | ✅ 5/5 |
| **`#42` `debt_status` 保留** | **✅**（本輪未被放寬） |
| `#43` `returned` 與實際筆數一致 | ✅ |
| `#44` `weight_version`／`score_scale`／`score_schema` | ✅（`v5.10` / `relative-within-version` / `1`） |
| `#47` 錯誤形狀、`#48` OpenAPI 完整性、`#49` `opMode` 預設 | ✅ ✅ ✅ |
| `#53` `summary` 7 維完備、無空值、`hobby` 為 list | ✅ 4/4；applied↔回傳一致 ✅ 1/1 |
| `#54` `housing_cost` 可進 `applied_filters` | 資訊列 |
| `#56` 停止原因合法/一致、連續空轉 ≤2 | ✅ 4/4 |
| **`#57` 核心維度保護** | ✅ 欄位齊備；**不變式（保護維度未被放寬）成立**；veto 路徑檢查 ✅（本輪未觸發 veto → ℹ️） |
| **`#58` `status` 語意**（`matched==0 ⇔ status!='ok'`） | ✅ |
| **`#59` enum／OpenAPI** | ✅ 含 `protected_dims`、`protected_veto`；回應值皆在 enum 內 |
| **`#60` root logger（`LOG_LEVEL` 轉發）** | ✅ `Protected dims=9`、`Broadening loop=17`，容器 `LOG_LEVEL=INFO` |
| **`#61` TESLA `commute_mode` 保護** | ✅ 保護集含 `commute_mode`，且**未被放寬** |
| `#55` 例外型別診斷碼、`#50` 部署版本/finish_reason | ✅ ✅ |

### 3.1 我額外加驗、upstream 沒有驗的不變式

`verify-extended.py`（本輪擴充到 A–P 檢查）全部通過，其中四項是 upstream 未涵蓋的：

| 檢查 | 內容 | 結果 |
|:--|:--|:--|
| **K** | `vetoed_dims ⊆ protected_dims`（veto 只能針對受保護維度） | ✅ |
| **L** | `protected_veto=True` 的 attempt 必有非空 `vetoed_dims` | ✅ |
| **M** | **veto 必須是 rollback**：`no_op=True`、`filters_changed=False`、`match_count` 不變 | ✅ |
| **G/H** | `no_op`／`overshoot` 旗標與 `match_count_before/after` 一致 | ✅ 10/10 輪 |
| A–F, I, J, N, O, P | 回應內外欄位一致性、`protected ∩ relaxed = ∅`、enum 涵蓋、`status` 語意 | ✅ |

---

## 4. API response 分析

> 級別：**【證據】**＝有 N≥3 取樣分布、機制性證明或可完整計數；**【觀察】**＝單次執行所見，**不可歸因**；**【空轉】**＝檢定本身無效。
> 本輪的「N≥3」來自 §4.7 的重現性探針（案例 6、案例 7 各 3 次）。

### 4.1 語意正確性 —— 逐案例問「這個 filter 對得上題意嗎？」

| 檢查 | 案例 | 結果 | 級別 |
|:--|:--|:--|:--|
| **must-use 成立** | 06 醫美 | `aesthetic_procedure=['有']`；且列為 **protected** | **【證據】**（主套件 + 探針 4 次都成立） |
| **must-use 成立** | 07 債務整合 | `debt_status=['有房貸','房貸+消費債']`；**protected 且未被放寬** | **【證據】**（4/4 次） |
| **must-use 成立** | 09 業主本人 | `employment_status=['雇主','自營作業者']`；protected | 【觀察】（單次） |
| **must-not-use 成立** | 01 藥妝零售 | 未套 `aesthetic_procedure`；reasoning 明說「未涉及醫美療程」 | 【觀察】 |
| **must-not-use 成立** | 08 小吃攤（顧客語意） | 未套 `employment_status`；reasoning 明說「主體是顧客而非攤商業者」 | 【觀察】 |
| **方向相反** | 04 房仲 vs 05 銀行 | 04 套 `housing_burden=['低']`、05 套 `['中','高']`；05 另套 `debt_status=['有房貸',…]`（轉貸戶） | 【觀察】 |
| **語意關鍵維度受保護** | 02 TESLA | `commute_mode=['汽車']` 且列為 protected —— reasoning 也說需要「通勤方式」 | 【觀察】 |

**`reasoning` 與實作的一致性**：機械抽取（自述「必須／需使用 X」的句子 vs `relaxed_dims`）比對，
**本輪 9 個案例沒有任何一件「自述必要卻被放寬」**（第九輪同型態有 5/9 案例）。
⚠️ 抽取用的正規表示式**不處理否定**，因此案例 01 的「**不需**使用 employment_status」會被誤判為
「自述必須用」——該誤判未被計入，且 01 本來就沒有放寬該維度。**【證據】**（就這 9 個案例的可計數結果）

**殘留的語意鬆動（一項，屬觀察）**：案例 06 的 loop2 把 `sex` 由 `['女']` **放寬值集**為 `['女','男']`，
而同案例的 reasoning 說「通常以女性、25-54 歲、中高收入為主」。
因為這是「值集放寬」而非「移除維度」，它**不會進 `relaxed_dims`**，也就不受任何檢查涵蓋
（本輪回應的 10 筆恰好全是女性，故實務後果為零）。**【觀察】**（單次；機制可複驗）

### 4.2 自證性 —— 用回傳列驗證 `applied_filters`

**13/13 項通過** ✅ —— 每個套用的維度，其回傳值都落在 filter 值域內。**【證據】**

| 案例 | 檢查（節錄） |
|:--|:--|
| 02 | `commute_mode=['汽車'] → {'汽車': 3}` ✓ |
| 05 | `debt_status=['有房貸','房貸+消費債'] → {'有房貸': 4, '房貸+消費債': 1}` ✓ |
| 06 | `sex=['女','男'] → {'女': 10}` ✓（見上述放寬值集） |
| 07 | `debt_status=['有房貸','房貸+消費債'] → {'有房貸': 9, '房貸+消費債': 1}` ✓ |
| 09 | `employment_status=['雇主','自營作業者'] → {'雇主': 10}` ✓ |

**可驗證性缺口：無。** `PersonaSummary` 曝露 24 欄，本輪所有 `applied_filters`／`dims_counted`
維度**全部落在** `summary` 曝露欄位內（`verify-extended.py` 檢查 [D]：9/9 通過）。

### 4.3 計分宣告誠實性 —— 必須區分兩種 mismatch

| 案例 | 列數 | 具檢定效力的配對 | **(a) 同分不同向量（碰撞）** | **(b) 同向量不同分（低報）** |
|:--|--:|--:|--:|--:|
| 09 業主 | 10 | **7** | **3** | **0** |
| 03 時尚 | 10 | 1 | 0 | 0 |
| 07 債務 | 10 | 1 | 0 | 0 |
| 08 小吃攤 | 10 | 1 | 0 | 0 |
| 01 / 02 / 04 / 05 / 06 | 3/3/5/5/10 | **0** | — | — |
| **合計** | — | **10** | **3** | **0** |

- **(b) 低報 = 0 ⇒ 沒有發現「有未列出的維度在影響計分」**。**【證據】**（就這 10 個配對）
- **(a) 碰撞 = 3**（全在案例 09）：不同屬性組合恰好同分 —— 依定義**合法、非缺陷**，
  但正好說明「同分」不能推論「同向量」，兩種 mismatch 必須分開看。
- **必須主動宣告**：9 個案例中有 **5 個是【空轉】**（配對數 0），檢定效力只來自 4 個案例、10 個配對。
- `score_scale = relative-within-version` ⇒ **分數只在同一次回應內有意義**。

### 4.4 Broadening 行為

| 指標 | 值 | 級別 |
|:--|:--|:--|
| 總放寬輪數 | 10（5/9 案例進入迴圈） | **【證據】** |
| **空轉率（`no_op`）** | **0/10 = 0%** | **【證據】** |
| **`overshoot`** | **0/10 = 0%** | **【證據】** |
| 「每輪最多移除 1 維度」（#25 cap） | 成立（`relaxed_dims` 數 ≤ 輪數，9/9） | **【證據】** |
| `no_op`／`overshoot` 旗標與數字一致 | **10/10 輪**（我的延伸檢查 G/H；upstream 未驗） | **【證據】** |

**放寬的維度選擇**：本輪每一輪的 `change` 文字都**明確論證「核心 vs 非核心」**，
實際被移除的都是非核心維度（`occupation`、`marriage`、`age`、`clothing_spend`、`income`、`family_income`）。
沒有任何一輪試圖移除受保護維度（故主套件未觸發 veto）。**【證據】**（10 輪文字皆可複驗）

### 4.5 頭部集中 —— 同一批 persona 是否跨題重複

**8 / 54 個回傳過的 persona 出現在 ≥2 個案例**【證據】（可完整計數）：

| persona | 次數 | 出現在 |
|:--|--:|:--|
| `TW-P-0234` | **4** | TESLA（汽車）、時尚服飾、房貸(銀行)、債務整合 |
| `TW-P-0473` | **3** | 房貸(銀行)、醫美、債務整合 |
| `TW-P-0331` | **3** | 房貸(銀行)、債務整合、業主受訪者(B2B) |
| 另有 5 個 | 2 | 見 `analyze.py` §6.5 輸出 |

姓名重複：`艾力克`×4、`志強`×4、`小艾`×3、`莉亞`×3、`米亞`×3。

### 4.6 其他觀察

**(1) `status` 語意是本輪最乾淨的一項**【證據】

逐筆驗證 **18 筆回應（主套件 9 + 探針 9）**：`matched == 0 ⇔ status != 'ok'` **18/18 成立、0 違反**。
3 筆 `matched=0` 的回應都正確回 `status='too_strict'`。

| 回應 | `matched` | `status` | `pool_exhausted` |
|:--|--:|:--|:--|
| 探針 `t1`（極窄查詢） | 0 | **`'too_strict'`** | True |
| 探針 `t2`（極窄查詢, top_k=100） | 0 | **`'too_strict'`** | True |
| 探針 `r07_debt_1`（重跑落入空池） | 0 | **`'too_strict'`** | True |
| 其餘 15 筆 | >0 | `'ok'` | — |

**(2) 硬性 veto 路徑成立（主套件沒涵蓋，靠定向探針逼出來）**【證據】

探針 `t1`：

```
stop_reason   = 'protected_veto'      ← 主套件 9 案例完全沒出現過這個值
protected_dims= ['clothing_spend','employment_status','family_income','income','sex']
loop1         = 0→0  no_op=True  filters_changed=False  protected_veto=True  vetoed_dims=['employment_status']
```

模型試圖移除**受保護的** `employment_status` → 系統**還原該輪並停止**。
我額外驗證了 upstream 沒驗的四項不變式（§3.1 的 K/L/M）都成立：`vetoed_dims ⊆ protected_dims`、
veto 必有非空 `vetoed_dims`、且 veto 確實是一次 rollback。伺服器端 log 亦對得上。

**(3) `applied_filters` 可出現「空值清單」，等同「全部排除」**【證據（機制）／觀察（頻率）】

18 筆中有 **1 筆**（探針 `r07_debt_1`）含空值清單：

```json
"applied_filters": {"age": [], "income": [">8萬"], "family_income": [], "housing_burden": ["中","高"], "debt_status": ["有房貸","房貸+消費債"]}
```

- **機制（源碼層證明）**：`persona_matcher.filter_personas()` 對字串型維度做
  `if val not in accepted: match = False`；當 `accepted == []` 時 `val not in []` **恆為真**
  ⇒ **該維度排除所有人**。這解釋了同一回應的 `loop2: 6→0` 與最終 `matched=0`。
- **沒有機制阻止它**：`_vetoed_dims` 只檢查**受保護**維度（`age`／`family_income` 不在保護集內），
  而空清單在字面上像「沒有指定值」，容易被讀成「該維度不限制」。
- **頻率 1/18，屬【觀察】**；「空清單＝排除全部」的語意本身是**【證據】**（源碼可證）。

**(4) `broadening_stop_reason` 仍有兩個不可達的值**【源碼層證據，非回應可觀測】

| 值 | 可達性 | 依據（部署碼 sha 已驗） |
|:--|:--|:--|
| `""`（空字串） | **不可達** | 兩個 `CandidatesResponse` 回傳點都帶入 `stop_reason`；迴圈後 `if not stop_reason:` 會補值 |
| `budget_limit` | **不可達** | `tokens_spent=12000`、`TOKEN_BUDGET=40000`、`broaden_max_tokens=8000`、`max_loops=3` ⇒ 預算只能在跑滿 3 輪後擋住下一輪，分類順序會先命中 `loop_limit` |

（**更正延續**：第九輪已指出同一件事，本輪在 v5.10 重新以源碼驗證仍成立。）

**(5) 案例 08（小吃攤）的 `protected_dims` 是空的**【觀察】

其餘 8 個案例都至少有一個受保護維度。本輪 08 沒有進入放寬迴圈，故無實際後果；
但意味著**若它需要放寬，沒有任何維度受保護**。可能原因：該題的領域強化與 reasoning 判準都沒點出核心維度。

### 4.7 §6.8 重現性探針 與 §6.9 定向探針

#### §6.8 重現性

**案例 06（醫美）：4 次執行**【證據】

| 執行 | `matched` | `relaxed_dims` | `stop_reason` | `protected_dims` |
|:--|--:|:--|:--|:--|
| 主套件 | 14 | `[clothing_spend, income]` | `loop_limit` | `[aesthetic_procedure]` |
| 探針 r1 | 14 | `[family_income, clothing_spend]` | `loop_limit` | `[aesthetic_procedure]` |
| 探針 r2 | 16 | `[age]` | **`protected_veto`** | `[aesthetic_procedure]` |
| 探針 r3 | 14 | `[occupation, sex]` | `loop_limit` | `[aesthetic_procedure]` |

→ **`protected_dims` 4/4 完全相同**（核心維度認定穩定）；`matched` 14–16。
但 **`relaxed_dims` 每次都不同**、`stop_reason` 也會變 ⇒ 單次的「這題放寬了什麼」只是【觀察】。

**案例 07（債務整合）：4 次執行**【證據】

| 執行 | `matched` | `relaxed_dims` | `stop_reason` | `protected ∩ relaxed` |
|:--|--:|:--|:--|:--|
| 主套件 | 30 | `[age, family_income]` | `target_reached` | ✅ ∅ |
| 探針 r1 | **0** | `[]` | `loop_limit` | ✅ ∅ |
| 探針 r2 | 14 | `[age]` | `loop_limit` | ✅ ∅ |
| 探針 r3 | 14 | `[age]` | `loop_limit` | ✅ ∅ |

→ **關鍵不變式 `protected ∩ relaxed = ∅` 4/4 成立**；**`debt_status` 4/4 都被套用且值集正確**
（`['有房貸','房貸+消費債']`）。但 `matched` 在 **0–30** 之間，再次說明單次數字不可靠。

#### §6.9 定向探針 —— 逼出主套件未涵蓋的分支

| 探針 | 設計意圖 | 實際結果 | 判定 |
|:--|:--|:--|:--|
| `t1` 極窄查詢 top_k=10 | 逼出 `matched=0` → 驗 `#58` | 200，`matched=0`、`status='too_strict'`、`pool_exhausted=True`、**`stop='protected_veto'`**、`vetoed_dims=['employment_status']` | ✅ 達標，**且額外逼出硬 veto 路徑** |
| `t2` 同查詢 top_k=100 | 逼出 `pool_exhausted=true` | 200，`matched=0`、`status='too_strict'`、`pool_exhausted=True`、`stop='no_op_limit'`（連續 2 輪空轉） | ✅ 達標 |
| `t3` TESLA top_k=20 | 逼放寬迴圈去動 `commute_mode`（`#61`） | 200，`matched=15`、`returned=15`、`pool_exhausted=True`、`stop='loop_limit'`、`relaxed=[marriage, occupation, clothing_spend]`、**`commute_mode` 未被放寬** | ✅ 達標 |

主套件只涵蓋 `{target_reached, loop_limit}`；三個探針把涵蓋擴到
`{too_strict(status), protected_veto, no_op_limit}` 與 `pool_exhausted=True`。

---

## 5. 驗證限制 / 未涵蓋範圍

**必須明說「沒驗到什麼」—— N/A ≠ 通過。**

1. **`broadening_stop_reason` 只觀測到 3 種值**（`target_reached`、`loop_limit`、`protected_veto`）。
   另外 4 種（`llm_empty`、`llm_parse_error`、`llm_no_filters`、`no_filters`）**未觸發**；
   其中 `""` 與 `budget_limit` 經源碼推論**不可達**（§4.6 (4)）→ **本輪無法判定這 4 種分支的行為**。
2. **`no_filters` 的觸發條件未實測**（需「初始 filters 為空」，主套件與探針都沒造出這種請求）。
3. **案例 06／07 的單次數字不可靠**：`matched` 分別為 14–16 與 **0–30**；`relaxed_dims` 每次都不同。
4. **案例 07 的 `matched=0` 只出現 1/4 次**，成因分布未能判定。
5. **`#53` 的「applied 維度 ↔ 回傳值一致」只被行使 1 次**（僅「小吃攤」的 `marriage` 落在檢查的 7 維內）。
6. **空值清單只觀測到 1/18**（§4.6 (3)）；機制已由源碼證明，但**頻率未知**；
   也未測試「空清單 + 受保護維度」的組合（依 superset 規則應被 veto，但未實測）。
7. **只測了 `opMode=僅篩選`**；`篩選+模擬`、`模擬詢問` 完全未執行。
8. **未測**：並發／rate limit、認證、5xx 重試語意、`/personadb/detail`、`top_k` 極端值。
9. **分數不可跨回應比較**（`relative-within-version`）。
10. **單一節點、單一部署、單一時段**。
11. **本輪有一個嚴重的作業疏失**：第一次啟動時 runner 因寫死 `OUT` 而**寫進第九輪的節點工作副本**。
    本機 master 與已發布的第九輪**均未受影響**（已驗證），該節點目錄已更名隔離。詳見 `meta/known-defects.txt` 缺陷 1。
12. **依 skill v2.1.0，本報告不做跨版本比對**。

---

## 6. 結論

### 6.1 這版好在哪（正面）

1. **核心維度保護機制真的有效**【證據】：兩個被探針的案例各 4 次執行，**核心維度認定 4/4 一致**、
   **`protected ∩ relaxed = ∅` 4/4 成立**；第九輪「把 `debt_status` 放寬掉、8→58 overshoot」**4/4 未再出現**；
   `#42` 由 ⚠️ 轉 ✅；`#61` 的 TESLA `commute_mode` 也受保護且未被放寬。
2. **硬性 veto 有牙齒**【證據】：探針 `t1` 逼出模型試圖移除受保護的 `employment_status` →
   系統**還原該輪並以 `protected_veto` 停止**。不再依賴模型自律，且 veto 是真正的 rollback。
3. **`status` 語意修好了**【證據】：`matched==0 ⇔ status!='ok'` 在 **18/18 筆**（含 3 筆空池）成立。
4. **放寬行為明顯收斂**【證據】：10 輪放寬中 **`no_op` 0 輪、`overshoot` 0 輪**；
   每輪自述都論證「核心 vs 非核心」，實際移除的都是非核心維度。
5. **自述與實作不再矛盾**【證據】：9 個案例 **0 件**「自述必要卻被放寬」。
6. **契約、錯誤處理、可觀測性乾淨**：**42 個斷言全過**、無 verifiability gap、`(b)` 低報 0、
   錯誤走統一 `ErrorResponse`、`#60` 讓 `Protected dims` 等 INFO 診斷真的進了 log（9 筆）。
7. **資料不足時不編造**：`matched=0` 回 `returned=0` + `status='too_strict'`。

### 6.2 這版要注意什麼

| # | 問題 | 級別 | 影響 |
|:--|:--|:--|:--|
| 1 | **同一 query 的 `matched` 變異仍極大**（案例 07：**0 ↔ 30**；案例 06：14–16） | **【證據】** | 單次 sweep 的數字不可作為品質結論 |
| 2 | **值集放寬沒有護欄、也不留痕**（案例 06 把 `sex` 由 `['女']` 放寬為 `['女','男']`） | 【觀察】 | 語意可能被悄悄放寬，且**不出現在 `relaxed_dims`** |
| 3 | **`applied_filters` 可含空值清單，等同「排除全部」** | 機制**【證據】**／頻率【觀察】 | 消費端可能把 `age: []` 讀成「不限制」，實際是 0 筆 |
| 4 | `broadening_stop_reason` 仍宣告 `""` 與 `budget_limit` 兩個**不可達**的值 | 源碼層證據 | 消費端 switch 會寫永遠不進去的分支 |
| 5 | 案例 08（小吃攤）的 `protected_dims` 為空 | 【觀察】 | 該題若需放寬，沒有任何維度受保護 |

### 6.3 建議

1. **把「值集放寬」也納入可觀測性**：目前只有「移除維度」才進 `relaxed_dims`；
   「放寬值集」（如 `sex: ['女'] → ['女','男']`）完全不留痕。建議另加欄位（如 `widened_dims`
   或在 attempt 內記 `value_widened`），讓消費端看得見語意被放寬了什麼。
2. **拒絕或修復空值清單**：`applied_filters` 出現 `[]` 時應視為「該維度未指定」而移除、或判定該輪無效重試
   —— 目前它會靜默地排除所有人。（`_vetoed_dims` 的 superset 規則已能擋住「受保護維度被清空」，非保護維度則無人管。）
3. **清掉不可達的 enum 值**（`""`、`budget_limit`），或調整分類順序讓它們真的可達。
4. **讓 `protected_dims` 對更多領域生效**：案例 08 完全沒有受保護維度，建議檢查該類題目的領域強化與 reasoning 抽取。
5. **品管流程加註取樣分布**：案例 07 的 0↔30 足以推翻任何單次判讀。

### 6.4 我對自己先前報告的更正

- **第九輪的三條建議已在本版落地，且本輪驗證為有效**：①「核心維度不可被放寬要變成機制」→ `protected_dims` + 硬 veto；
  ②「`status` 應反映實情」→ `matched==0` 不再回 `'ok'`；③「區分嘗試失敗與刻意拒絕」→ `protected_veto` vs `no_op_limit`。
- **第九輪指出 `""` 與 `budget_limit` 不可達**：本輪在 v5.10 重新以源碼驗證，**仍然成立**（§4.6 (4)）。
- **第九輪的作業疏失**（`run.log` 標題印成 tmpname）本輪**未重演**：執行前先跑
  `meta/test-runner-harness.sh` 驗「執行時行為」（11 項全過）。
- **本輪我自己新增的疏失**已記於 `meta/known-defects.txt`（`OUT` 寫死導致證據寫進上一輪目錄）。

---

## 7. 相對於原腳本的改動（儀器忠實度聲明）

除下列各項外，**請求參數、參數順序、斷言邏輯、案例標籤全部與 upstream 逐字相同**（§1.1 機械證明）：

| # | 改動 | 類別 | 說明 |
|:--|:--|:--|:--|
| 1 | 證據落盤：每個案例加 `-D headers/<case>.headers`、`-o raw/<case>.body`、`-w … > meta/<case>.w` | **落盤** | upstream 只有 `time curl … \| tee`，沒有 headers 與量測欄位 |
| 2 | 加 `-s` | 外觀 | 抑制進度表；不影響請求 |
| 3 | 案例 0 補一行標題 `=== 0. /personadb/status ===` | 外觀 | upstream 該案例無標題 |
| 4 | 案例 3 的 `jq` 美化輸出改落盤到 `json/03_fashion.json` | **落盤** | 該檔沒有任何斷言讀取 |
| 5 | 追加 `openapi.json` 快照 + `shasum` 一行 | 新增 | 供解讀回應與契約比對；不涉請求 |
| 6 | runner 環境變數化（`BASE_URL` / `OUT`）；`OUT` 預設**由目錄名推導** | 環境 | 本輪兩者皆為 upstream 原生值（`localhost:8000`、`$HOME/qa-round10`） |

**未改動**：`questions`/`top_k`/`role`/`opMode` 的參數值與順序（32 個 `data-urlencode` 逐一比對相同）、
`#34`–`#61` 與 `#50`/`#55`/`#60` 的斷言運算式、`/tmp/*.json` 的中介檔名。
